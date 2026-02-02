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
    let contactSheetGenerator = ContactSheetGenerator()

    var isProcessing = false
    var currentItem: MediaItem?
    var currentOperation = ""
    var processedCount = 0
    var totalCount = 0
    var errors: [(MediaItem, Error)] = []
    var operationLog: [AIOperationLog] = []

    private var cancelled = false

    func clearLog() {
        operationLog.removeAll()
    }

    // MARK: - Full Pipeline (Batch)

    func processItems(_ items: [MediaItem], settings: AppSettings, allTags: [String], library: MediaLibrary, modelContext: ModelContext) async {
        guard !items.isEmpty else { return }

        let xaiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName)
        let groqKey = KeychainService.load(key: KeychainService.groqAPIKeyName)

        guard xaiKey != nil else {
            Self.logger.warning("No xAI API key configured, skipping AI processing")
            return
        }

        isProcessing = true
        processedCount = 0
        totalCount = items.count
        errors = []
        cancelled = false

        for item in items {
            guard !cancelled else { break }
            currentItem = item

            // Step 1: Transcribe if video with audio (independent of tagging)
            if let groqKey, item.isVideo, item.hasAudio == true, item.transcriptText == nil {
                currentOperation = "Transcribing"
                do {
                    try await transcribeItem(item, groqKey: groqKey, model: settings.groqModel, library: library, modelContext: modelContext)
                    operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .success))
                } catch {
                    Self.logger.error("Transcription failed for \(item.originalFilename): \(self.describeError(error))")
                    errors.append((item, error))
                    operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .failure(describeError(error))))
                }
            }

            // Step 2: Tag and summarize (runs even if transcription failed)
            if let xaiKey {
                currentOperation = "Tagging"
                do {
                    try await tagItem(item, xaiKey: xaiKey, settings: settings, allTags: allTags, library: library, modelContext: modelContext)
                    operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Tag", status: .success))
                } catch {
                    Self.logger.error("Tagging failed for \(item.originalFilename): \(self.describeError(error))")
                    errors.append((item, error))
                    operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Tag", status: .failure(describeError(error))))
                }
            }

            processedCount += 1
        }

        currentItem = nil
        currentOperation = ""
        isProcessing = false
    }

    // MARK: - Transcribe-Only (Batch)

    func transcribeItems(_ items: [MediaItem], settings: AppSettings, library: MediaLibrary, modelContext: ModelContext) async {
        guard !items.isEmpty else { return }

        guard let groqKey = KeychainService.load(key: KeychainService.groqAPIKeyName) else {
            Self.logger.warning("No Groq API key configured, skipping transcription")
            return
        }

        isProcessing = true
        processedCount = 0
        totalCount = items.count
        errors = []
        cancelled = false

        for item in items {
            guard !cancelled else { break }
            currentItem = item
            currentOperation = "Transcribing"

            do {
                try await transcribeItem(item, groqKey: groqKey, model: settings.groqModel, library: library, modelContext: modelContext)
                operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .success))
            } catch {
                Self.logger.error("Transcription failed for \(item.originalFilename): \(self.describeError(error))")
                errors.append((item, error))
                operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .failure(describeError(error))))
            }

            processedCount += 1
        }

        currentItem = nil
        currentOperation = ""
        isProcessing = false
    }

    // MARK: - Single-Item Operations

    func tagItem(_ item: MediaItem, settings: AppSettings, allTags: [String], library: MediaLibrary, modelContext: ModelContext) async {
        guard let xaiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName) else {
            Self.logger.warning("No xAI API key configured")
            return
        }

        isProcessing = true
        currentItem = item
        currentOperation = "Tagging"
        totalCount = 1
        processedCount = 0
        errors = []

        do {
            try await tagItem(item, xaiKey: xaiKey, settings: settings, allTags: allTags, library: library, modelContext: modelContext)
            operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Tag", status: .success))
        } catch {
            Self.logger.error("Tagging failed for \(item.originalFilename): \(self.describeError(error))")
            errors = [(item, error)]
            operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Tag", status: .failure(describeError(error))))
        }

        processedCount = 1
        currentItem = nil
        currentOperation = ""
        isProcessing = false
    }

    func summarizeItem(_ item: MediaItem, settings: AppSettings, library: MediaLibrary, modelContext: ModelContext) async {
        guard let xaiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName) else { return }

        isProcessing = true
        currentItem = item
        currentOperation = "Summarizing"
        totalCount = 1
        processedCount = 0
        errors = []

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
            try modelContext.save()
            operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Summarize", status: .success))
        } catch {
            Self.logger.error("Summarization failed for \(item.originalFilename): \(self.describeError(error))")
            errors = [(item, error)]
            operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Summarize", status: .failure(describeError(error))))
        }

        processedCount = 1
        currentItem = nil
        currentOperation = ""
        isProcessing = false
    }

    func transcribeItem(_ item: MediaItem, settings: AppSettings, modelContext: ModelContext, library: MediaLibrary) async {
        guard let groqKey = KeychainService.load(key: KeychainService.groqAPIKeyName) else { return }
        guard item.isVideo, item.hasAudio == true else { return }

        isProcessing = true
        currentItem = item
        currentOperation = "Transcribing"
        totalCount = 1
        processedCount = 0
        errors = []

        do {
            let url = library.absoluteURL(for: item)
            let audioURL = try await transcriptionService.extractAudio(from: url)
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let result = try await transcriptionService.transcribe(audioURL: audioURL, model: settings.groqModel, apiKey: groqKey)
            item.transcriptText = result.text
            try modelContext.save()
            operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .success))
        } catch {
            Self.logger.error("Transcription failed for \(item.originalFilename): \(self.describeError(error))")
            errors = [(item, error)]
            operationLog.append(AIOperationLog(timestamp: Date(), itemName: item.originalFilename, operation: "Transcribe", status: .failure(describeError(error))))
        }

        processedCount = 1
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

    private func transcribeItem(_ item: MediaItem, groqKey: String, model: String, library: MediaLibrary, modelContext: ModelContext) async throws {
        guard item.transcriptText == nil else { return }

        let url = library.absoluteURL(for: item)

        Self.logger.info("Extracting audio from \(item.originalFilename) at \(url.path)")
        let audioURL = try await transcriptionService.extractAudio(from: url)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let audioSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
        Self.logger.info("Audio extracted: \(audioURL.lastPathComponent) (\(audioSize / 1_048_576)MB)")

        let result = try await transcriptionService.transcribe(audioURL: audioURL, model: model, apiKey: groqKey)
        item.transcriptText = result.text
        try modelContext.save()

        Self.logger.info("Transcribed \(item.originalFilename): \(result.text.prefix(80))...")
    }

    private func tagItem(_ item: MediaItem, xaiKey: String, settings: AppSettings, allTags: [String], library: MediaLibrary, modelContext: ModelContext) async throws {
        let url = library.absoluteURL(for: item)
        Self.logger.info("Tagging \(item.originalFilename) at \(url.path)")

        let constrainTags = settings.aiTagMode == .constrainToExisting ? allTags : nil
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

        // Apply results
        item.tags = result.tags.map { $0.lowercased() }
        item.summary = result.summary

        switch result.productionSource {
        case "studio": item.production = .professional
        case "creator": item.production = .creator
        case "homemade": item.production = .homemade
        default: break
        }

        try modelContext.save()
        Self.logger.info("Tagged \(item.originalFilename): \(result.tags.count) tags, production=\(result.productionSource)")
    }
}
