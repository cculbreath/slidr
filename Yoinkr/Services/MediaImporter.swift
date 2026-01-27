import Foundation
import SwiftData
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.culbreath.Yoinkr", category: "Import")

struct MediaImporter {
    private let libraryRoot: URL
    private let modelContext: ModelContext

    init(libraryRoot: URL, modelContext: ModelContext) {
        self.libraryRoot = libraryRoot
        self.modelContext = modelContext
    }

    func importFiles(urls: [URL]) async throws -> ImportResult {
        var result = ImportResult()

        for url in urls {
            do {
                // Check if supported
                guard let mediaType = await detectMediaType(url: url) else {
                    logger.warning("Unsupported file type: \(url.lastPathComponent)")
                    result.failed.append((url, ImportError.unsupportedFormat))
                    continue
                }

                // Generate content hash
                let hash = try ContentHasher.hash(fileAt: url)

                // Check for duplicate
                if isDuplicate(hash: hash) {
                    logger.info("Skipping duplicate: \(url.lastPathComponent)")
                    result.skippedDuplicates.append(url)
                    continue
                }

                // Get file attributes
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let modDate = attributes[.modificationDate] as? Date ?? Date()

                // Generate destination path
                let year = Calendar.current.component(.year, from: Date())
                let uuid = UUID().uuidString
                let ext = url.pathExtension.lowercased()
                let relativePath = "Local/\(year)/\(uuid).\(ext)"
                let destinationURL = libraryRoot.appendingPathComponent(relativePath)

                // Ensure year directory exists
                let yearDir = libraryRoot.appendingPathComponent("Local/\(year)")
                try FileManager.default.createDirectory(at: yearDir, withIntermediateDirectories: true)

                // Copy file
                try FileManager.default.copyItem(at: url, to: destinationURL)

                // Create MediaItem
                let item = MediaItem(
                    originalFilename: url.lastPathComponent,
                    relativePath: relativePath,
                    storageLocation: .local,
                    contentHash: hash,
                    fileSize: fileSize,
                    mediaType: mediaType,
                    fileModifiedDate: modDate
                )

                // Extract metadata based on type
                if mediaType == .video {
                    await extractVideoMetadata(url: destinationURL, item: item)
                } else if let dimensions = getImageDimensions(url: destinationURL) {
                    item.width = Int(dimensions.width)
                    item.height = Int(dimensions.height)
                }

                modelContext.insert(item)
                result.imported.append(item)

                logger.info("Imported: \(url.lastPathComponent)")

            } catch {
                logger.error("Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
                result.failed.append((url, error))
            }
        }

        try modelContext.save()
        return result
    }

    private func detectMediaType(url: URL) async -> MediaType? {
        guard let uti = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return nil
        }

        if uti.conforms(to: .gif) {
            return .gif
        } else if uti.conforms(to: .movie) || uti.conforms(to: .video) {
            // Verify it's actually a video with video track (not audio-only)
            let asset = AVURLAsset(url: url)
            let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            return videoTracks.isEmpty ? nil : .video
        } else if uti.conforms(to: .image) {
            return .image
        }

        return nil
    }

    private func isDuplicate(hash: String) -> Bool {
        let predicate = #Predicate<MediaItem> { $0.contentHash == hash }
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        descriptor.fetchLimit = 1
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    private func getImageDimensions(url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private func extractVideoMetadata(url: URL, item: MediaItem) async {
        let asset = AVURLAsset(url: url)

        do {
            // Load duration
            let duration = try await asset.load(.duration)
            item.duration = duration.seconds

            // Load tracks for dimensions and frame rate
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let videoTrack = videoTracks.first {
                let size = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)

                // Apply transform to get correct orientation
                let transformedSize = size.applying(transform)
                item.width = Int(abs(transformedSize.width))
                item.height = Int(abs(transformedSize.height))

                // Get frame rate
                let frameRate = try await videoTrack.load(.nominalFrameRate)
                item.frameRate = Double(frameRate)
            }

            // Check for audio track
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            item.hasAudio = !audioTracks.isEmpty

        } catch {
            logger.warning("Failed to extract video metadata for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

enum ImportError: LocalizedError {
    case unsupportedFormat
    case hashingFailed
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Unsupported file format"
        case .hashingFailed: return "Failed to generate file hash"
        case .copyFailed: return "Failed to copy file to library"
        }
    }
}

struct ImportResult: Sendable {
    var imported: [MediaItem] = []
    var skippedDuplicates: [URL] = []
    var failed: [(url: URL, error: Error)] = []

    var successCount: Int { imported.count }
    var failureCount: Int { failed.count }

    var summary: String {
        var parts: [String] = []
        if !imported.isEmpty { parts.append("\(imported.count) imported") }
        if !skippedDuplicates.isEmpty { parts.append("\(skippedDuplicates.count) duplicates skipped") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        return parts.joined(separator: ", ")
    }
}
