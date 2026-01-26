import Foundation
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.culbreath.Yoinkr", category: "Thumbnails")

actor ThumbnailCache {
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
        let task = Task<NSImage, Error> {
            let fileURL = libraryRoot.appendingPathComponent(item.relativePath)

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ThumbnailError.fileNotFound
            }

            let image = try generateThumbnail(url: fileURL, size: size)

            // Cache to disk
            if let jpegData = image.jpegData(compressionQuality: jpegQuality) {
                try? jpegData.write(to: diskPath)
            }

            // Cache to memory
            memoryCache.setObject(image, forKey: cacheKey as NSString)

            logger.debug("Generated thumbnail for \(item.originalFilename)")
            return image
        }

        generationTasks[cacheKey] = task

        defer {
            generationTasks.removeValue(forKey: cacheKey)
        }

        return try await task.value
    }

    private func generateThumbnail(url: URL, size: ThumbnailSize) throws -> NSImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ThumbnailError.failedToLoad
        }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: size.pixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ThumbnailError.failedToGenerate
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
