import Foundation
import AppKit
import ImageIO
import AVFoundation
import OSLog

actor ThumbnailCache {
    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "Thumbnails")

    private let cacheDirectory: URL
    private let memoryCache = NSCache<NSString, NSImage>()
    private var generationTasks: [String: Task<NSImage, Error>] = [:]

    private let maxMemoryCacheSize = 100
    private let jpegQuality: CGFloat = 0.8

    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        memoryCache.countLimit = maxMemoryCacheSize
    }

    func thumbnail(for item: MediaItem, size: ThumbnailSize, libraryRoot: URL) async throws -> NSImage {
        let cacheKey = "\(item.contentHash)-\(size.rawValue)"

        // 1. Check memory cache
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // 2. Check if generation already in progress
        if let existingTask = generationTasks[cacheKey] {
            return try await existingTask.value
        }

        // 3. Check disk cache
        let diskPath = cacheDirectory.appendingPathComponent("\(cacheKey).jpg")
        if FileManager.default.fileExists(atPath: diskPath.path),
           let image = NSImage(contentsOf: diskPath) {
            memoryCache.setObject(image, forKey: cacheKey as NSString)
            return image
        }

        // 4. Generate thumbnail
        // Capture values to avoid crossing isolation boundaries
        let pixelSize = size.pixelSize
        let quality = jpegQuality
        let relativePath = item.relativePath
        let filename = item.originalFilename
        let mediaType = item.mediaType

        let task = Task<NSImage, Error> {
            let fileURL = libraryRoot.appendingPathComponent(relativePath)

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ThumbnailError.fileNotFound
            }

            let image: NSImage
            switch mediaType {
            case .video:
                image = try await Self.generateVideoThumbnail(url: fileURL, pixelSize: pixelSize)
            case .image, .gif:
                let cgImage = try Self.generateCGImage(url: fileURL, pixelSize: pixelSize)
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }

            // Cache to disk
            if let tiffData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality]) {
                try? jpegData.write(to: diskPath)
            }

            // Cache to memory
            memoryCache.setObject(image, forKey: cacheKey as NSString)

            Self.logger.debug("Generated thumbnail for \(filename)")
            return image
        }

        generationTasks[cacheKey] = task

        defer {
            generationTasks.removeValue(forKey: cacheKey)
        }

        return try await task.value
    }

    private static func generateCGImage(url: URL, pixelSize: CGFloat) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ThumbnailError.failedToLoad
        }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ThumbnailError.failedToGenerate
        }

        return cgImage
    }

    private static func generateVideoThumbnail(url: URL, pixelSize: CGFloat) async throws -> NSImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)

        // Get thumbnail from 10% into the video (avoids black frames at start)
        let duration = try await asset.load(.duration)
        let time = CMTime(seconds: duration.seconds * 0.1, preferredTimescale: duration.timescale)

        let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Scrub Thumbnail Disk Cache

    func cachedScrubThumbnails(forHash hash: String, count: Int) -> [NSImage]? {
        var images: [NSImage] = []
        for i in 0..<count {
            let path = cacheDirectory.appendingPathComponent("\(hash)-scrub-\(i).jpg")
            guard let image = NSImage(contentsOf: path) else { return nil }
            images.append(image)
        }
        return images
    }

    func hasScrubThumbnails(forHash hash: String, count: Int) -> Bool {
        let firstPath = cacheDirectory.appendingPathComponent("\(hash)-scrub-0.jpg")
        let lastPath = cacheDirectory.appendingPathComponent("\(hash)-scrub-\(count - 1).jpg")
        let fm = FileManager.default
        return fm.fileExists(atPath: firstPath.path) && fm.fileExists(atPath: lastPath.path)
    }

    func videoScrubThumbnails(for item: MediaItem, count: Int, size: ThumbnailSize, libraryRoot: URL) async throws -> [NSImage] {
        guard item.isVideo else {
            throw ThumbnailError.invalidMedia
        }

        let hash = item.contentHash

        // Check disk cache first
        if let cached = cachedScrubThumbnails(forHash: hash, count: count) {
            return cached
        }

        let fileURL = libraryRoot.appendingPathComponent(item.relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ThumbnailError.fileNotFound
        }

        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.pixelSize, height: size.pixelSize)

        let duration = try await asset.load(.duration)
        let interval = duration.seconds / Double(count + 1)

        var thumbnails: [NSImage] = []

        for i in 1...count {
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: duration.timescale)
            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                thumbnails.append(image)

                // Write to disk cache
                if let tiffData = image.tiffRepresentation,
                   let bitmapRep = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]) {
                    let diskPath = cacheDirectory.appendingPathComponent("\(hash)-scrub-\(i - 1).jpg")
                    try? jpegData.write(to: diskPath)
                }
            } catch {
                Self.logger.warning("Failed to generate scrub thumbnail at \(time.seconds)s: \(error.localizedDescription)")
            }
        }

        return thumbnails
    }

    func preGenerateScrubThumbnails(for items: [PreGenerateItem], count: Int, libraryRoot: URL) async {
        let pixelSize = ThumbnailSize.medium.pixelSize
        var generated = 0

        for item in items {
            if hasScrubThumbnails(forHash: item.contentHash, count: count) {
                continue
            }

            let fileURL = libraryRoot.appendingPathComponent(item.relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            do {
                let asset = AVURLAsset(url: fileURL)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)

                let duration = try await asset.load(.duration)
                let interval = duration.seconds / Double(count + 1)

                for i in 1...count {
                    let time = CMTime(seconds: interval * Double(i), preferredTimescale: duration.timescale)
                    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                    let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

                    if let tiffData = image.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffData),
                       let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality]) {
                        let diskPath = cacheDirectory.appendingPathComponent("\(item.contentHash)-scrub-\(i - 1).jpg")
                        try? jpegData.write(to: diskPath)
                    }
                }
                generated += 1
                Self.logger.debug("Pre-generated scrub thumbnails for \(item.filename)")
            } catch {
                Self.logger.warning("Failed to pre-generate scrub thumbnails for \(item.filename): \(error.localizedDescription)")
            }
        }

        if generated > 0 {
            Self.logger.info("Pre-generated scrub thumbnails for \(generated) videos")
        }
    }

    func clearScrubThumbnails() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }

        var removedCount = 0
        for file in files where file.lastPathComponent.contains("-scrub-") {
            try? FileManager.default.removeItem(at: file)
            removedCount += 1
        }

        if removedCount > 0 {
            Self.logger.info("Cleared \(removedCount) scrub thumbnail files")
        }
    }

    func removeThumbnails(forHash hash: String) {
        // Remove standard thumbnails
        for size in ThumbnailSize.allCases {
            let key = "\(hash)-\(size.rawValue)" as NSString
            memoryCache.removeObject(forKey: key)

            let path = cacheDirectory.appendingPathComponent("\(hash)-\(size.rawValue).jpg")
            try? FileManager.default.removeItem(at: path)
        }

        // Remove scrub thumbnails
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        let prefix = "\(hash)-scrub-"
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func diskCacheSize() -> Int {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var totalSize = 0
        for file in files {
            if let resources = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = resources.fileSize {
                totalSize += size
            }
        }
        return totalSize
    }

    func clearCache() {
        memoryCache.removeAllObjects()

        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "jpg" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Cache Management

    func diskCacheCount() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return 0 }

        return files.filter { $0.pathExtension == "jpg" }.count
    }

    func pruneOrphanedThumbnails(existingHashes: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        var removedCount = 0
        for fileURL in files where fileURL.pathExtension == "jpg" {
            let filename = fileURL.deletingPathExtension().lastPathComponent
            let hash = extractHash(from: filename)
            if !existingHashes.contains(hash) {
                try? FileManager.default.removeItem(at: fileURL)
                memoryCache.removeObject(forKey: filename as NSString)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            Self.logger.info("Pruned \(removedCount) orphaned thumbnails")
        }
    }

    func enforceMaxSize(maxBytes: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let jpgFiles = files.filter { $0.pathExtension == "jpg" }

        struct CacheFile {
            let url: URL
            let size: Int
            let modDate: Date
        }

        let cacheFiles: [CacheFile] = jpgFiles.compactMap { fileURL in
            guard let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = resources.fileSize,
                  let modDate = resources.contentModificationDate else { return nil }
            return CacheFile(url: fileURL, size: size, modDate: modDate)
        }

        let totalSize = cacheFiles.reduce(0) { $0 + $1.size }
        guard totalSize > maxBytes else { return }

        let sorted = cacheFiles.sorted { $0.modDate < $1.modDate }

        var currentSize = totalSize
        var removedCount = 0

        for file in sorted {
            guard currentSize > maxBytes else { break }
            try? FileManager.default.removeItem(at: file.url)
            let cacheKey = file.url.deletingPathExtension().lastPathComponent as NSString
            memoryCache.removeObject(forKey: cacheKey)
            currentSize -= file.size
            removedCount += 1
        }

        if removedCount > 0 {
            Self.logger.info("Enforced max cache size: removed \(removedCount) files, freed \(totalSize - currentSize) bytes")
        }
    }

    // MARK: - Private Helpers

    private func extractHash(from cacheKey: String) -> String {
        // Handle scrub thumbnail pattern: {hash}-scrub-{index}
        if let scrubRange = cacheKey.range(of: "-scrub-") {
            return String(cacheKey[cacheKey.startIndex..<scrubRange.lowerBound])
        }

        // Handle standard thumbnail pattern: {hash}-{size}
        for size in ThumbnailSize.allCases {
            let suffix = "-\(size.rawValue)"
            if cacheKey.hasSuffix(suffix) {
                return String(cacheKey.dropLast(suffix.count))
            }
        }
        return cacheKey
    }
}

/// Sendable value type for passing media item data across isolation boundaries
struct PreGenerateItem: Sendable {
    let contentHash: String
    let relativePath: String
    let filename: String
}

enum ThumbnailError: LocalizedError {
    case fileNotFound
    case failedToLoad
    case failedToGenerate
    case invalidMedia

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "File not found"
        case .failedToLoad: return "Failed to load image"
        case .failedToGenerate: return "Failed to generate thumbnail"
        case .invalidMedia: return "Invalid media type"
        }
    }
}
