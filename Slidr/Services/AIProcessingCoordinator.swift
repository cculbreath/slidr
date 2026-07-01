import Foundation
import OSLog
import SwiftData
import SwiftOpenAI

struct AIOperationLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let itemName: String
    let operation: String
    let status: Status

    enum Status {
        case success
        case failure(String)
    }
}

@MainActor
@Observable
final class AIProcessingCoordinator {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "AIProcessing")

    let taggingService = AITaggingService()
    let transcriptionService = WhisperTranscriptionService()
    let mistralTranscriptionService = MistralTranscriptionService()
    let contactSheetGenerator = ContactSheetGenerator()

    var transcriptStore: TranscriptStore?

    var isProcessing = false
    var currentItem: MediaItem?
    var currentOperation = ""
    var processedCount = 0
    var totalCount = 0
    var errors: [(MediaItem, Error)] = []
    var operationLog: [AIOperationLog] = []

    /// Non-item-specific problem that blocks a run before it starts (e.g. a
    /// missing API key). Surfaced in the sidebar so misconfiguration no longer
    /// fails silently. Cleared when a run actually begins or the user dismisses it.
    var configError: String?

    private var cancelled = false

    /// Save and log-flush cadence: persist + surface accumulated log entries
    /// every N processed items, with a final save/flush after the batch.
    private static let batchInterval = 20

    /// Log entries accumulated between flushes. Appending here does not trigger
    /// SwiftUI invalidation; entries are surfaced to `operationLog` in batches to
    /// avoid re-rendering the status list on every single item.
    private var pendingLog: [AIOperationLog] = []

    func clearLog() {
        pendingLog.removeAll()
        operationLog.removeAll()
        errors.removeAll()
        configError = nil
    }

    func dismissConfigError() {
        configError = nil
    }

    /// Reset per-run state at the start of a batch. Clears the previous run's log
    /// and any stale config notice so the sidebar reflects only the current run.
    private func beginBatch(total: Int) {
        isProcessing = true
        processedCount = 0
        totalCount = total
        errors = []
        operationLog = []
        pendingLog = []
        configError = nil
        cancelled = false
    }

    /// Set `currentOperation` only when the label actually changes, so identical
    /// per-item writes don't trigger redundant SwiftUI invalidation.
    private func setOperation(_ operation: String) {
        if currentOperation != operation {
            currentOperation = operation
        }
    }

    /// Move buffered log entries into the observed `operationLog` in one mutation.
    private func flushLog() {
        guard !pendingLog.isEmpty else { return }
        operationLog.append(contentsOf: pendingLog)
        pendingLog.removeAll(keepingCapacity: true)
    }

    /// Persist mutated model objects and surface buffered log entries together.
    /// Called at batch boundaries and once more after the loop completes.
    private func commitBatch(_ modelContext: ModelContext) {
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Batch save failed: \(self.describeError(error))")
        }
        flushLog()
    }

    // MARK: - Full Pipeline (Batch)

    func processItems(_ items: [MediaItem], settings: AppSettings, library: MediaLibrary, modelContext: ModelContext) async {
        guard !items.isEmpty else { return }

        let xaiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName)

        guard xaiKey != nil else {
            configError = "No xAI API key configured. Add one in Settings › AI to tag or summarize media."
            Self.logger.warning("No xAI API key configured, skipping AI processing")
            return
        }

        beginBatch(total: items.count)
        defer { commitBatch(modelContext) }

        for item in items {
            guard !cancelled else { break }
            currentItem = item

            // Step 1: Transcribe if video with audio (independent of tagging)
            if item.isVideo, item.hasAudio == true, item.transcriptText == nil {
                setOperation("Transcribing")
                do {
                    try await transcribeItem(item, settings: settings, library: library)
                    pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .success))
                } catch {
                    Self.logger.error("Transcription failed for \(item.originalFilename): \(self.describeError(error))")
                    errors.append((item, error))
                    pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .failure(describeError(error))))
                }
            }

            // Step 2: Tag and summarize (runs even if transcription failed)
            if let xaiKey {
                setOperation("Tagging")
                do {
                    try await tagItem(item, xaiKey: xaiKey, settings: settings, library: library)
                    pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Tag", status: .success))
                } catch {
                    Self.logger.error("Tagging failed for \(item.originalFilename): \(self.describeError(error))")
                    errors.append((item, error))
                    pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Tag", status: .failure(describeError(error))))
                }
            }

            processedCount += 1
            if processedCount % Self.batchInterval == 0 {
                commitBatch(modelContext)
            }
        }

        currentItem = nil
        currentOperation = ""
        isProcessing = false
    }

    // MARK: - Transcribe-Only (Batch)

    func transcribeItems(_ items: [MediaItem], settings: AppSettings, library: MediaLibrary, modelContext: ModelContext) async {
        guard !items.isEmpty else { return }

        let hasKey: Bool
        switch settings.transcriptionProvider {
        case .groqWhisper:
            hasKey = KeychainService.exists(key: KeychainService.groqAPIKeyName)
        case .mistral:
            hasKey = KeychainService.exists(key: KeychainService.mistralAPIKeyName)
        }
        guard hasKey else {
            configError = "No \(settings.transcriptionProvider.displayName) API key configured. Add one in Settings › AI to transcribe."
            Self.logger.warning("No API key configured for \(settings.transcriptionProvider.displayName), skipping transcription")
            return
        }

        beginBatch(total: items.count)
        defer { commitBatch(modelContext) }

        setOperation("Transcribing")
        for item in items {
            guard !cancelled else { break }
            currentItem = item

            do {
                try await transcribeItem(item, settings: settings, library: library)
                pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .success))
            } catch {
                Self.logger.error("Transcription failed for \(item.originalFilename): \(self.describeError(error))")
                errors.append((item, error))
                pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .failure(describeError(error))))
            }

            processedCount += 1
            if processedCount % Self.batchInterval == 0 {
                commitBatch(modelContext)
            }
        }

        currentItem = nil
        currentOperation = ""
        isProcessing = false
    }

    // MARK: - Tag-Only (Batch)

    func tagItems(_ items: [MediaItem], settings: AppSettings, library: MediaLibrary, modelContext: ModelContext) async {
        guard !items.isEmpty else { return }

        guard let xaiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName) else {
            configError = "No xAI API key configured. Add one in Settings › AI to tag media."
            Self.logger.warning("No xAI API key configured")
            return
        }

        beginBatch(total: items.count)
        defer { commitBatch(modelContext) }

        setOperation("Tagging")
        for item in items {
            guard !cancelled else { break }
            currentItem = item

            do {
                try await tagItem(item, xaiKey: xaiKey, settings: settings, library: library)
                pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Tag", status: .success))
            } catch {
                Self.logger.error("Tagging failed for \(item.originalFilename): \(self.describeError(error))")
                errors.append((item, error))
                pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Tag", status: .failure(describeError(error))))
            }

            processedCount += 1
            if processedCount % Self.batchInterval == 0 {
                commitBatch(modelContext)
            }
        }

        currentItem = nil
        currentOperation = ""
        isProcessing = false
    }

    // MARK: - Summarize-Only (Batch)

    func summarizeItems(_ items: [MediaItem], settings: AppSettings, library: MediaLibrary, modelContext: ModelContext) async {
        guard !items.isEmpty else { return }

        guard let xaiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName) else {
            configError = "No xAI API key configured. Add one in Settings › AI to summarize media."
            Self.logger.warning("No xAI API key configured")
            return
        }

        beginBatch(total: items.count)
        defer { commitBatch(modelContext) }

        setOperation("Summarizing")
        for item in items {
            guard !cancelled else { break }
            currentItem = item

            do {
                let url = library.absoluteURL(for: item)
                let imageData: Data

                if item.isVideo {
                    guard let sheet = try await contactSheetGenerator.generateOverviewSheet(from: url, mediaType: .video) else {
                        throw AITaggingError.contactSheetFailed
                    }
                    imageData = sheet
                } else if item.isAnimated {
                    guard let sheet = try await contactSheetGenerator.generateOverviewSheet(from: url, mediaType: .gif) else {
                        throw AITaggingError.contactSheetFailed
                    }
                    imageData = sheet
                } else {
                    guard let sheet = try await contactSheetGenerator.generateOverviewSheet(from: url, mediaType: .image) else {
                        throw AITaggingError.contactSheetFailed
                    }
                    imageData = sheet
                }

                let summary = try await taggingService.summarize(imageData: imageData, model: settings.aiModel, apiKey: xaiKey)
                item.summary = summary
                // Persisted in batches below.
                pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Summarize", status: .success))
            } catch {
                Self.logger.error("Summarization failed for \(item.originalFilename): \(self.describeError(error))")
                errors.append((item, error))
                pendingLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Summarize", status: .failure(describeError(error))))
            }

            processedCount += 1
            if processedCount % Self.batchInterval == 0 {
                commitBatch(modelContext)
            }
        }

        currentItem = nil
        currentOperation = ""
        isProcessing = false
    }

    func cancel() {
        cancelled = true
    }

    /// Extract a meaningful description from any error, including SwiftOpenAI's APIError
    /// which doesn't conform to LocalizedError.
    private func describeError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.displayDescription
        }
        if let localizedError = error as? LocalizedError, let desc = localizedError.errorDescription {
            return desc
        }
        let desc = error.localizedDescription
        // Detect generic NSError messages and replace with the actual error type info
        if desc.contains("The operation could") || desc.contains("The operation couldn") {
            return String(describing: error)
        }
        return desc
    }

    // MARK: - Internal Helpers

    private func transcribeItem(_ item: MediaItem, settings: AppSettings, library: MediaLibrary) async throws {
        guard item.transcriptText == nil else { return }

        let url = library.absoluteURL(for: item)

        Self.logger.info("Extracting audio from \(item.originalFilename) at \(url.path)")
        let audioURL = try await transcriptionService.extractAudio(from: url)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let audioSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        Self.logger.info("Audio extracted: \(audioURL.lastPathComponent) (\(audioSize / 1_048_576)MB)")

        let result: TranscriptionResult
        switch settings.transcriptionProvider {
        case .groqWhisper:
            guard let apiKey = KeychainService.load(key: KeychainService.groqAPIKeyName) else {
                throw TranscriptionError.noAPIKey(provider: "Groq")
            }
            result = try await transcriptionService.transcribe(audioURL: audioURL, model: settings.groqModel, apiKey: apiKey)
        case .mistral:
            guard let apiKey = KeychainService.load(key: KeychainService.mistralAPIKeyName) else {
                throw TranscriptionError.noAPIKey(provider: "Mistral")
            }
            result = try await mistralTranscriptionService.transcribe(audioURL: audioURL, model: settings.mistralModel, apiKey: apiKey)
        }

        // Save SRT file via TranscriptStore for timed subtitle display
        if let transcriptStore, !result.srtContent.isEmpty {
            let storeResult = try await transcriptStore.saveTranscript(
                srtContent: result.srtContent,
                forContentHash: item.contentHash
            )
            item.transcriptText = storeResult.plainText
            item.transcriptRelativePath = storeResult.relativePath
        } else {
            item.transcriptText = result.text
        }

        // Persisted in batches by the calling loop.
        Self.logger.info("Transcribed \(item.originalFilename): \(result.text.prefix(80))...")
    }

    private func tagItem(_ item: MediaItem, xaiKey: String, settings: AppSettings, library: MediaLibrary) async throws {
        let url = library.absoluteURL(for: item)
        Self.logger.info("Tagging \(item.originalFilename) at \(url.path)")

        // Always source the constraint set from the full library — never from a
        // filtered grid view — so the JSON-schema enum truly reflects every known tag.
        // Lowercase + dedupe to match the post-write normalization further down,
        // so model output round-trips identically to the canonical stored tag.
        let constrainTags: [String]?
        if settings.aiTagMode == .constrainToExisting {
            let normalized = Array(Set(library.allTags.map { $0.lowercased() })).sorted()
            constrainTags = normalized
            Self.logger.info("Tag constraint active: \(normalized.count) library tags")
        } else {
            constrainTags = nil
        }
        let result: AITagResult

        if item.isVideo {
            result = try await taggingService.tagVideo(
                videoURL: url,
                transcript: item.transcriptText,
                existingTags: constrainTags,
                tagMode: settings.aiTagMode,
                model: settings.aiModel,
                apiKey: xaiKey
            )
        } else {
            let imageData: Data
            if item.isAnimated {
                guard let sheet = try await contactSheetGenerator.generateOverviewSheet(from: url, mediaType: .gif) else {
                    throw AITaggingError.contactSheetFailed
                }
                imageData = sheet
            } else {
                guard let sheet = try await contactSheetGenerator.generateOverviewSheet(from: url, mediaType: .image) else {
                    throw AITaggingError.contactSheetFailed
                }
                imageData = sheet
            }

            result = try await taggingService.tagImage(
                imageData: imageData,
                existingTags: constrainTags,
                tagMode: settings.aiTagMode,
                model: settings.aiModel,
                apiKey: xaiKey
            )
        }

        // Apply results — in constrain mode, defensively drop any tag not in the
        // allow-list. xAI's strict JSON-schema enum is not always honored end-to-end
        // (e.g. the model has been observed pluralizing "tattoo" → "tattoos"), so
        // we enforce the constraint client-side too.
        var finalTags = result.tags.map { $0.lowercased() }
        if let allowList = constrainTags {
            let allowed = Set(allowList)
            let rejected = finalTags.filter { !allowed.contains($0) }
            if !rejected.isEmpty {
                Self.logger.warning("Dropped \(rejected.count) tag(s) outside library allow-list for \(item.originalFilename): \(rejected.joined(separator: ", "))")
            }
            finalTags = finalTags.filter { allowed.contains($0) }
        }
        item.tags = finalTags
        item.summary = result.summary

        switch result.productionSource {
        case "studio": item.production = .professional
        case "creator": item.production = .creator
        case "homemade": item.production = .homemade
        default: break
        }

        // Persisted in batches by the calling loop.
        Self.logger.info("Tagged \(item.originalFilename): \(result.tags.count) tags, production=\(result.productionSource)")
    }
}
