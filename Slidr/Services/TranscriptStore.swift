import Foundation
import SwiftUI
import OSLog

actor TranscriptStore {
    private let transcriptDirectory: URL
    private var cueCache: [String: [TranscriptCue]] = [:]

    init(transcriptDirectory: URL) {
        self.transcriptDirectory = transcriptDirectory
    }

    /// Imports a transcript file, copying it to the transcript directory.
    /// Returns parsed cues, plain text for search, and the relative path for storage.
    func importTranscript(
        from sourceURL: URL,
        forContentHash contentHash: String
    ) throws -> (cues: [TranscriptCue], plainText: String, relativePath: String) {
        let ext = sourceURL.pathExtension.lowercased()
        guard TranscriptFormat(fileExtension: ext) != nil else {
            throw TranscriptError.unsupportedFormat
        }

        let destinationFilename = "\(contentHash).\(ext)"
        let destinationURL = transcriptDirectory.appendingPathComponent(destinationFilename)

        // Remove existing transcript file if present
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let cues = try TranscriptParser.parse(fileAt: destinationURL)
        let plainText = TranscriptParser.extractPlainText(from: cues)

        // Cache the parsed cues
        cueCache[contentHash] = cues

        Logger.transcripts.info("Imported transcript for \(contentHash): \(cues.count) cues")

        return (cues: cues, plainText: plainText, relativePath: destinationFilename)
    }

    /// Loads cues from disk and caches them.
    func loadCues(forContentHash contentHash: String, relativePath: String) throws -> [TranscriptCue] {
        let fileURL = transcriptDirectory.appendingPathComponent(relativePath)
        let cues = try TranscriptParser.parse(fileAt: fileURL)
        cueCache[contentHash] = cues
        return cues
    }

    /// Returns cached cues or loads from disk.
    func cues(forContentHash contentHash: String, relativePath: String) throws -> [TranscriptCue] {
        if let cached = cueCache[contentHash] {
            return cached
        }
        return try loadCues(forContentHash: contentHash, relativePath: relativePath)
    }

    /// Removes a transcript file from disk and clears the cache.
    func removeTranscript(forContentHash contentHash: String, relativePath: String) {
        let fileURL = transcriptDirectory.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: fileURL)
        cueCache.removeValue(forKey: contentHash)
        Logger.transcripts.info("Removed transcript for \(contentHash)")
    }
}

// MARK: - Environment Integration

private struct TranscriptStoreKey: EnvironmentKey {
    static let defaultValue: TranscriptStore? = nil
}

extension EnvironmentValues {
    var transcriptStore: TranscriptStore? {
        get { self[TranscriptStoreKey.self] }
        set { self[TranscriptStoreKey.self] = newValue }
    }
}
