import AVFoundation
import Foundation
import OSLog

actor VideoConverter {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "VideoConverter")
    static let incompatibleFormats: Set<String> = [
        "avi", "wmv", "flv", "mkv", "webm", "3gp", "asf", "vob"
    ]

    static let compatibleFormats: Set<String> = [
        "mp4", "m4v", "mov", "qt"
    ]

    struct ConversionProgress {
        let sourceURL: URL
        let progress: Double
        let status: ConversionStatus
    }

    enum ConversionStatus {
        case pending
        case converting
        case completed(URL)
        case failed(Error)
    }

    enum ConversionError: LocalizedError {
        case unsupportedFormat(String)
        case exportFailed(String)
        case noVideoTrack
        case cancelled

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let format): return "Unsupported video format: \(format)"
            case .exportFailed(let reason): return "Export failed: \(reason)"
            case .noVideoTrack: return "No video track found in file"
            case .cancelled: return "Conversion was cancelled"
            }
        }
    }

    static func needsConversion(url: URL) -> Bool {
        incompatibleFormats.contains(url.pathExtension.lowercased())
    }

    static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return compatibleFormats.contains(ext) || incompatibleFormats.contains(ext)
    }

    func convert(
        sourceURL: URL,
        outputDirectory: URL,
        targetFormat: VideoFormat = .h264MP4,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        Self.logger.info("Converting: \(sourceURL.lastPathComponent) to \(targetFormat.displayName)")

        let asset = AVURLAsset(url: sourceURL)
        guard let _ = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.noVideoTrack
        }

        let outputFilename = sourceURL.deletingPathExtension().lastPathComponent + "." + targetFormat.fileExtension
        let outputURL = outputDirectory.appendingPathComponent(outputFilename)
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: targetFormat.exportPreset
        ) else {
            throw ConversionError.exportFailed("Could not create export session")
        }

        exportSession.shouldOptimizeForNetworkUse = true

        let progressTask = Task {
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 100_000_000)
                progress?(Double(exportSession.progress))
            }
        }

        do {
            try await exportSession.export(to: outputURL, as: targetFormat.fileType)
            progressTask.cancel()
            Self.logger.info("Conversion complete: \(outputURL.lastPathComponent)")
            progress?(1.0)
            return outputURL
        } catch is CancellationError {
            progressTask.cancel()
            throw ConversionError.cancelled
        } catch {
            progressTask.cancel()
            Self.logger.error("Conversion failed: \(error.localizedDescription)")
            throw ConversionError.exportFailed(error.localizedDescription)
        }
    }

    func convertBatch(
        sourceURLs: [URL],
        outputDirectory: URL,
        targetFormat: VideoFormat = .h264MP4,
        progress: (@Sendable (Int, Int, Double) -> Void)? = nil
    ) async throws -> [URL] {
        var results: [URL] = []
        for (index, sourceURL) in sourceURLs.enumerated() {
            let outputURL = try await convert(sourceURL: sourceURL, outputDirectory: outputDirectory, targetFormat: targetFormat) { itemProgress in
                progress?(index, sourceURLs.count, itemProgress)
            }
            results.append(outputURL)
        }
        return results
    }
}
