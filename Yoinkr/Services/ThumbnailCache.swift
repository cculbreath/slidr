import Foundation
import AppKit
import ImageIO
import AVFoundation
import OSLog

actor ThumbnailCache {
    private static let logger = Logger(subsystem: "com.culbreath.Yoinkr", category: "Thumbnails")

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

    func videoScrubThumbnails(for item: MediaItem, count: Int, size: ThumbnailSize, libraryRoot: URL) async throws -> [NSImage] {
        guard item.isVideo else {
            throw ThumbnailError.invalidMedia
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
            } catch {
                Self.logger.warning("Failed to generate scrub thumbnail at \(time.seconds)s: \(error.localizedDescription)")
            }
        }

        return thumbnails
    }

    func removeThumbnails(forHash hash: String) {
        for size in ThumbnailSize.allCases {
            let key = "\(hash)-\(size.rawValue)" as NSString
            memoryCache.removeObject(forKey: key)

            let path = cacheDirectory.appendingPathComponent("\(hash)-\(size.rawValue).jpg")
            try? FileManager.default.removeItem(at: path)
        }
    }

    func clearCache() {
        memoryCache.removeAllObjects()

        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "jpg" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
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
