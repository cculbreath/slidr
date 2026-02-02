import Foundation
import OSLog
import SwiftData

@MainActor
@Observable
final class AIProcessingCoordinator {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "AIProcessing")

    let taggingService = AITaggingService()
    let transcriptionService = WhisperTranscriptionService()
    let contactSheetGenerator = ContactSheetGenerator()

    var isProcessing = false
    var currentItem: MediaItem?
    var processedCount = 0
    var totalCount = 0
    var errors: [(MediaItem, Error)] = []

    private var cancelled = false

    // MARK: - Full Pipeline (Batch)

    func processItems(_ items: [MediaItem], settings: AppSettings, allTags: [String], modelContext: ModelContext) async {
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

            do {
                // Step 1: Transcribe if video with audio
                if let groqKey, item.isVideo, item.hasAudio == true, item.transcriptText == nil {
                    try await transcribeItem(item, groqKey: groqKey, model: settings.groqModel, modelContext: modelContext)
                }

                // Step 2: Tag and summarize
                if let xaiKey {
                    try await tagItem(item, xaiKey: xaiKey, settings: settings, allTags: allTags, modelContext: modelContext)
                }
            } catch {
                Self.logger.error("Processing failed for \(item.originalFilename): \(error.localizedDescription)")
                errors.append((item, error))
            }

            processedCount += 1
        }

        currentItem = nil
        isProcessing = false
    }

    // MARK: - Transcribe-Only (Batch)

    func transcribeItems(_ items: [MediaItem], settings: AppSettings, modelContext: ModelContext) async {
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

            do {
                try await transcribeItem(item, groqKey: groqKey, model: settings.groqModel, modelContext: modelContext)
            } catch {
                Self.logger.error("Transcription failed for \(item.originalFilename): \(error.localizedDescription)")
                errors.append((item, error))
            }

            processedCount += 1
        }

        currentItem = nil
        isProcessing = false
    }

    // MARK: - Single-Item Operations

    func tagItem(_ item: MediaItem, settings: AppSettings, allTags: [String], modelContext: ModelContext) async {
        guard let xaiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName) else {
            Self.logger.warning("No xAI API key configured")
            return
        }

        isProcessing = true
        currentItem = item
        totalCount = 1
        processedCount = 0

        do {
            try await tagItem(item, xaiKey: xaiKey, settings: settings, allTags: allTags, modelContext: modelContext)
        } catch {
            Self.logger.error("Tagging failed for \(item.originalFilename): \(error.localizedDescription)")
            errors = [(item, error)]
        }

        processedCount = 1
        currentItem = nil
        isProcessing = false
    }

    func summarizeItem(_ item: MediaItem, settings: AppSettings, library: MediaLibrary, modelContext: ModelContext) async {
        guard let xaiKey = KeychainService.load(key: KeychainService.xaiAPIKeyName) else { return }

        isProcessing = true
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
            try modelContext.save()
        } catch {
            Self.logger.error("Summarization failed for \(item.originalFilename): \(error.localizedDescription)")
        }

        currentItem = nil
        isProcessing = false
    }

    func transcribeItem(_ item: MediaItem, settings: AppSettings, modelContext: ModelContext, library: MediaLibrary) async {
        guard let groqKey = KeychainService.load(key: KeychainService.groqAPIKeyName) else { return }
        guard item.isVideo, item.hasAudio == true else { return }

        isProcessing = true
        currentItem = item

        do {
            let url = library.absoluteURL(for: item)
            let audioURL = try await transcriptionService.extractAudio(from: url)
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let result = try await transcriptionService.transcribe(audioURL: audioURL, model: settings.groqModel, apiKey: groqKey)
            item.transcriptText = result.text
            try modelContext.save()
        } catch {
            Self.logger.error("Transcription failed for \(item.originalFilename): \(error.localizedDescription)")
        }

        currentItem = nil
        isProcessing = false
    }

    func cancel() {
        cancelled = true
    }

    // MARK: - Internal Helpers

    private func transcribeItem(_ item: MediaItem, groqKey: String, model: String, modelContext: ModelContext) async throws {
        guard item.transcriptText == nil else { return }

        // Need the URL from library — use relativePath to construct it
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let libraryDir = appSupport.appendingPathComponent("Slidr/Library", isDirectory: true)
        let url: URL

        switch item.storageLocation {
        case .local:
            url = libraryDir.appendingPathComponent("Local").appendingPathComponent(item.relativePath)
        case .external:
            url = libraryDir.appendingPathComponent("External").appendingPathComponent(item.relativePath)
        case .referenced:
            url = URL(fileURLWithPath: item.relativePath)
        }

        let audioURL = try await transcriptionService.extractAudio(from: url)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let result = try await transcriptionService.transcribe(audioURL: audioURL, model: model, apiKey: groqKey)
        item.transcriptText = result.text
        try modelContext.save()

        Self.logger.info("Transcribed \(item.originalFilename): \(result.text.prefix(80))...")
    }

    private func tagItem(_ item: MediaItem, xaiKey: String, settings: AppSettings, allTags: [String], modelContext: ModelContext) async throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let libraryDir = appSupport.appendingPathComponent("Slidr/Library", isDirectory: true)
        let url: URL

        switch item.storageLocation {
        case .local:
            url = libraryDir.appendingPathComponent("Local").appendingPathComponent(item.relativePath)
        case .external:
            url = libraryDir.appendingPathComponent("External").appendingPathComponent(item.relativePath)
        case .referenced:
            url = URL(fileURLWithPath: item.relativePath)
        }

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
