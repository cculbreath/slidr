import Foundation
import SwiftData
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics
import AVFoundation
import OSLog

struct ImportProgress: Sendable {
    let currentItem: Int
    let totalItems: Int
    let currentFilename: String
    let phase: Phase

    enum Phase: Sendable {
        case importing
        case converting(progress: Double)
        case extractingMetadata
    }

    var overallProgress: Double {
        let base = Double(currentItem) / Double(max(totalItems, 1))
        switch phase {
        case .importing:
            return base
        case .converting(let progress):
            return base + (progress / Double(max(totalItems, 1)))
        case .extractingMetadata:
            return base + (0.9 / Double(max(totalItems, 1)))
        }
    }
}

struct MediaImporter {
    private let libraryRoot: URL
    private let modelContext: ModelContext
    private let videoConverter = VideoConverter()
    private let options: ImportOptions

    init(libraryRoot: URL, modelContext: ModelContext, options: ImportOptions = .default) {
        self.libraryRoot = libraryRoot
        self.modelContext = modelContext
        self.options = options

        let convertedDir = libraryRoot.appendingPathComponent("Converted")
        try? FileManager.default.createDirectory(at: convertedDir, withIntermediateDirectories: true)
    }

    func importFiles(urls: [URL]) async throws -> ImportResult {
        return try await importFiles(urls: urls, progressHandler: nil)
    }

    func importFiles(
        urls: [URL],
        progressHandler: (@Sendable (ImportProgress) -> Void)?
    ) async throws -> ImportResult {
        var result = ImportResult()

        for (index, url) in urls.enumerated() {
            do {
                progressHandler?(ImportProgress(
                    currentItem: index,
                    totalItems: urls.count,
                    currentFilename: url.lastPathComponent,
                    phase: .importing
                ))

                let needsVideoConversion = options.convertIncompatible && VideoConverter.needsConversion(url: url)

                guard let mediaType = await detectMediaType(url: url) else {
                    Logger.importing.warning("Unsupported file type: \(url.lastPathComponent)")
                    result.failed.append((url, ImportError.unsupportedFormat))
                    continue
                }

                let hash = try ContentHasher.hash(fileAt: url)

                if isDuplicate(hash: hash) {
                    Logger.importing.info("Skipping duplicate: \(url.lastPathComponent)")
                    result.skippedDuplicates.append(url)
                    continue
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let modDate = attributes[.modificationDate] as? Date ?? Date()

                var importURL = url
                var finalExtension = url.pathExtension.lowercased()

                if needsVideoConversion {
                    progressHandler?(ImportProgress(
                        currentItem: index,
                        totalItems: urls.count,
                        currentFilename: url.lastPathComponent,
                        phase: .converting(progress: 0)
                    ))

                    let convertedDir = libraryRoot.appendingPathComponent("Converted")
                    let convertedURL = try await videoConverter.convert(
                        sourceURL: url,
                        outputDirectory: convertedDir,
                        targetFormat: options.targetFormat
                    ) { conversionProgress in
                        progressHandler?(ImportProgress(
                            currentItem: index,
                            totalItems: urls.count,
                            currentFilename: url.lastPathComponent,
                            phase: .converting(progress: conversionProgress)
                        ))
                    }
                    importURL = convertedURL
                    finalExtension = options.targetFormat.fileExtension
                    result.converted.append(url)
                    Logger.importing.info("Converted \(url.lastPathComponent) to \(options.targetFormat.displayName)")
                }

                progressHandler?(ImportProgress(
                    currentItem: index,
                    totalItems: urls.count,
                    currentFilename: url.lastPathComponent,
                    phase: .extractingMetadata
                ))

                let dateForOrg = options.organizeByDate ? modDate : Date()
                let year = Calendar.current.component(.year, from: dateForOrg)
                let uuid = UUID().uuidString
                let relativePath: String
                if options.organizeByDate {
                    let month = Calendar.current.component(.month, from: dateForOrg)
                    relativePath = "Local/\(year)/\(String(format: "%02d", month))/\(uuid).\(finalExtension)"
                } else {
                    relativePath = "Local/\(year)/\(uuid).\(finalExtension)"
                }
                let destinationURL = libraryRoot.appendingPathComponent(relativePath)
                let destinationDir = destinationURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

                try FileManager.default.copyItem(at: importURL, to: destinationURL)

                // Clean up converted temp file after copying to library
                if needsVideoConversion {
                    try? FileManager.default.removeItem(at: importURL)
                }

                let item = MediaItem(
                    originalFilename: url.lastPathComponent,
                    relativePath: relativePath,
                    storageLocation: .local,
                    contentHash: hash,
                    fileSize: fileSize,
                    mediaType: mediaType,
                    fileModifiedDate: modDate
                )

                if mediaType == .gif {
                    if let gifMeta = GIFDecoder.metadata(url: destinationURL) {
                        item.width = Int(gifMeta.size.width)
                        item.height = Int(gifMeta.size.height)
                        item.duration = gifMeta.duration
                        item.frameCount = gifMeta.frameCount
                    }
                } else if mediaType == .video {
                    await extractVideoMetadata(url: destinationURL, item: item)
                } else if let dimensions = getImageDimensions(url: destinationURL) {
                    item.width = Int(dimensions.width)
                    item.height = Int(dimensions.height)
                }

                modelContext.insert(item)
                result.imported.append(item)

                Logger.importing.info("Imported: \(url.lastPathComponent)")

            } catch {
                Logger.importing.error("Failed to import \(url.lastPathComponent): \(error.localizedDescription)")
                result.failed.append((url, error))
            }
        }

        try modelContext.save()
        return result
    }

    // MARK: - External Drive Support

    func importFromExternalDrive(urls: [URL]) async throws -> ImportResult {
        var result = ImportResult()

        for url in urls {
            do {
                guard ExternalDriveManager.isExternalDrive(url) else {
                    Logger.importing.warning("Not an external drive path: \(url.path)")
                    result.failed.append((url, ImportError.unsupportedFormat))
                    continue
                }

                guard let mediaType = await detectMediaType(url: url) else {
                    Logger.importing.warning("Unsupported file type: \(url.lastPathComponent)")
                    result.failed.append((url, ImportError.unsupportedFormat))
                    continue
                }

                let hash = try ContentHasher.hash(fileAt: url)

                if isDuplicate(hash: hash) {
                    Logger.importing.info("Skipping duplicate: \(url.lastPathComponent)")
                    result.skippedDuplicates.append(url)
                    continue
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let modDate = attributes[.modificationDate] as? Date ?? Date()

                guard let volumeName = ExternalDriveManager.volumeName(for: url) else {
                    result.failed.append((url, ImportError.copyFailed))
                    continue
                }

                let volumeRoot = URL(fileURLWithPath: "/Volumes/\(volumeName)")
                let relativeToVolume = url.path.replacingOccurrences(of: volumeRoot.path, with: "")
                let relativePath = "External/\(volumeName)\(relativeToVolume)"

                let destinationURL = libraryRoot.appendingPathComponent(relativePath)
                let destinationDir = destinationURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

                try FileManager.default.copyItem(at: url, to: destinationURL)

                let item = MediaItem(
                    originalFilename: url.lastPathComponent,
                    relativePath: relativePath,
                    storageLocation: .external,
                    contentHash: hash,
                    fileSize: fileSize,
                    mediaType: mediaType,
                    fileModifiedDate: modDate
                )

                if mediaType == .gif {
                    if let gifMeta = GIFDecoder.metadata(url: destinationURL) {
                        item.width = Int(gifMeta.size.width)
                        item.height = Int(gifMeta.size.height)
                        item.duration = gifMeta.duration
                        item.frameCount = gifMeta.frameCount
                    }
                } else if mediaType == .video {
                    await extractVideoMetadata(url: destinationURL, item: item)
                } else if let dimensions = getImageDimensions(url: destinationURL) {
                    item.width = Int(dimensions.width)
                    item.height = Int(dimensions.height)
                }

                modelContext.insert(item)
                result.imported.append(item)

                Logger.importing.info("Imported from external drive: \(url.lastPathComponent)")

            } catch {
                Logger.importing.error("Failed to import from external \(url.lastPathComponent): \(error.localizedDescription)")
                result.failed.append((url, error))
            }
        }

        try modelContext.save()
        return result
    }

    func importAsReferences(urls: [URL]) async throws -> ImportResult {
        var result = ImportResult()

        for url in urls {
            do {
                guard let mediaType = await detectMediaType(url: url) else {
                    Logger.importing.warning("Unsupported file type: \(url.lastPathComponent)")
                    result.failed.append((url, ImportError.unsupportedFormat))
                    continue
                }

                let hash = try ContentHasher.hash(fileAt: url)

                if isDuplicate(hash: hash) {
                    Logger.importing.info("Skipping duplicate: \(url.lastPathComponent)")
                    result.skippedDuplicates.append(url)
                    continue
                }

                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                let modDate = attributes[.modificationDate] as? Date ?? Date()

                // For references, store the absolute path directly
                let item = MediaItem(
                    originalFilename: url.lastPathComponent,
                    relativePath: url.path,
                    storageLocation: .referenced,
                    contentHash: hash,
                    fileSize: fileSize,
                    mediaType: mediaType,
                    fileModifiedDate: modDate
                )

                if mediaType == .gif {
                    if let gifMeta = GIFDecoder.metadata(url: url) {
                        item.width = Int(gifMeta.size.width)
                        item.height = Int(gifMeta.size.height)
                        item.duration = gifMeta.duration
                        item.frameCount = gifMeta.frameCount
                    }
                } else if mediaType == .video {
                    await extractVideoMetadata(url: url, item: item)
                } else if let dimensions = getImageDimensions(url: url) {
                    item.width = Int(dimensions.width)
                    item.height = Int(dimensions.height)
                }

                modelContext.insert(item)
                result.imported.append(item)

                Logger.importing.info("Referenced: \(url.lastPathComponent)")

            } catch {
                Logger.importing.error("Failed to reference \(url.lastPathComponent): \(error.localizedDescription)")
                result.failed.append((url, error))
            }
        }

        try modelContext.save()
        return result
    }

    // MARK: - Media Type Detection

    private func detectMediaType(url: URL) async -> MediaType? {
        // Check for incompatible video formats that can be converted
        if VideoConverter.needsConversion(url: url) {
            return .video
        }

        guard let uti = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return nil
        }

        if uti.conforms(to: .gif) {
            return .gif
        } else if uti.conforms(to: .movie) || uti.conforms(to: .video) {
            let asset = AVURLAsset(url: url)
            let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            return videoTracks.isEmpty ? nil : .video
        } else if uti.conforms(to: .image) {
            return .image
        }

        return nil
    }

    // MARK: - Helpers

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
            let duration = try await asset.load(.duration)
            item.duration = duration.seconds

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            if let videoTrack = videoTracks.first {
                let size = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)

                let transformedSize = size.applying(transform)
                item.width = Int(abs(transformedSize.width))
                item.height = Int(abs(transformedSize.height))

                let frameRate = try await videoTrack.load(.nominalFrameRate)
                item.frameRate = Double(frameRate)
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            item.hasAudio = !audioTracks.isEmpty

        } catch {
            Logger.importing.warning("Failed to extract video metadata for \(url.lastPathComponent): \(error.localizedDescription)")
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
    var converted: [URL] = []
    var failed: [(url: URL, error: Error)] = []

    var successCount: Int { imported.count }
    var failureCount: Int { failed.count }

    var summary: String {
        var parts: [String] = []
        if !imported.isEmpty { parts.append("\(imported.count) imported") }
        if !converted.isEmpty { parts.append("\(converted.count) converted") }
        if !skippedDuplicates.isEmpty { parts.append("\(skippedDuplicates.count) duplicates skipped") }
        if !failed.isEmpty { parts.append("\(failed.count) failed") }
        return parts.joined(separator: ", ")
    }
}
