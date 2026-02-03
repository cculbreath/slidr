import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.physicscloud.slidr", category: "CaptionAudioImport")

@MainActor
final class CaptionAudioImporter {
    private let modelContext: ModelContext
    private let libraryRoot: URL

    init(modelContext: ModelContext, libraryRoot: URL) {
        self.modelContext = modelContext
        self.libraryRoot = libraryRoot
    }

    struct ImportResult {
        var captionsMatched = 0
        var audioFilesCopied = 0
        var itemsNotFound = 0
        var errors: [String] = []
    }

    enum ImportError: LocalizedError {
        case missingCaptionsJSON
        case missingAudioDirectory

        var errorDescription: String? {
            switch self {
            case .missingCaptionsJSON:
                return "No captions_only.json found in the selected folder."
            case .missingAudioDirectory:
                return "No audio/ subdirectory found in the selected folder."
            }
        }
    }

    /// Import from a folder that contains `captions_only.json` and an `audio/` subdirectory.
    func importFromFolder(_ folderURL: URL) async throws -> ImportResult {
        let jsonURL = folderURL.appendingPathComponent("captions_only.json")
        let audioDir = folderURL.appendingPathComponent("audio", isDirectory: true)

        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw ImportError.missingCaptionsJSON
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: audioDir.path, isDirectory: &isDir), isDir.boolValue else {
            throw ImportError.missingAudioDirectory
        }

        return try await importCaptionsAndAudio(jsonURL: jsonURL, audioDir: audioDir)
    }

    private func importCaptionsAndAudio(jsonURL: URL, audioDir: URL) async throws -> ImportResult {
        var result = ImportResult()

        let jsonData = try Data(contentsOf: jsonURL)
        let entries = try JSONDecoder().decode([CaptionEntry].self, from: jsonData)

        logger.info("Loaded \(entries.count) caption entries")

        let audioCaptionsDir = libraryRoot.appendingPathComponent("AudioCaptions", isDirectory: true)
        try FileManager.default.createDirectory(at: audioCaptionsDir, withIntermediateDirectories: true)

        for entry in entries {
            guard entry.hasCaptions else { continue }

            let basename = (entry.filename as NSString).deletingPathExtension

            let descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate { item in
                    item.relativePath.contains(basename)
                }
            )

            guard let mediaItem = try modelContext.fetch(descriptor).first else {
                result.itemsNotFound += 1
                continue
            }

            // Set imageText from captions (concatenate multiple with newlines)
            let captionTexts = entry.captions.map { $0.text }
            mediaItem.imageText = captionTexts.joined(separator: "\n")
            result.captionsMatched += 1

            // Copy audio file if it exists
            let audioSourceURL = audioDir.appendingPathComponent("\(basename).mp3")
            if FileManager.default.fileExists(atPath: audioSourceURL.path) {
                let audioRelativePath = "AudioCaptions/\(basename).mp3"
                let audioDestURL = libraryRoot.appendingPathComponent(audioRelativePath)

                if !FileManager.default.fileExists(atPath: audioDestURL.path) {
                    try FileManager.default.copyItem(at: audioSourceURL, to: audioDestURL)
                }

                mediaItem.audioCaptionRelativePath = audioRelativePath
                result.audioFilesCopied += 1
            }
        }

        try modelContext.save()
        logger.info("Import complete: \(result.captionsMatched) captions, \(result.audioFilesCopied) audio files, \(result.itemsNotFound) not found")

        return result
    }
}

// MARK: - JSON Models

private struct CaptionEntry: Decodable {
    let filename: String
    let hasCaptions: Bool
    let captions: [Caption]
    let narratorGender: String?

    enum CodingKeys: String, CodingKey {
        case filename
        case hasCaptions = "has_caption"
        case captions
        case narratorGender = "narrator_gender"
    }
}

private struct Caption: Decodable {
    let text: String
    let frameNumber: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case frameNumber = "frame_number"
    }
}
