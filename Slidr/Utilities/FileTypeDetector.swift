import UniformTypeIdentifiers
import Foundation

struct FileTypeDetector {
    static func detectType(for url: URL) -> MediaType? {
        let ext = url.pathExtension.lowercased()

        if let type = typeFromExtension(ext) {
            return type
        }

        return typeFromUTI(url: url)
    }

    static func isSupported(_ url: URL) -> Bool {
        return detectType(for: url) != nil
    }

    private static func typeFromExtension(_ ext: String) -> MediaType? {
        switch ext {
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "bmp", "tiff", "tif":
            return .image
        case "gif":
            return .gif
        case "mp4", "m4v", "mov", "avi", "wmv", "mkv", "webm", "flv", "3gp":
            return .video
        default:
            return nil
        }
    }

    private static func typeFromUTI(url: URL) -> MediaType? {
        guard let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
              let utType = UTType(uti) else {
            return nil
        }

        if utType.conforms(to: .gif) {
            return .gif
        } else if utType.conforms(to: .movie) || utType.conforms(to: .video) {
            return .video
        } else if utType.conforms(to: .image) {
            return .image
        }

        return nil
    }

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "webp", "bmp", "tiff", "tif",
        "gif",
        "mp4", "m4v", "mov", "avi", "wmv", "mkv", "webm", "flv", "3gp"
    ]

    static let supportedUTTypes: [UTType] = [
        .image,
        .gif,
        .movie,
        .video,
        .mpeg4Movie,
        .quickTimeMovie,
        .avi
    ]

    static func isImage(_ url: URL) -> Bool {
        let type = detectType(for: url)
        return type == .image || type == .gif
    }

    static func isVideo(_ url: URL) -> Bool {
        return detectType(for: url) == .video
    }

    static func isAnimatedGIF(_ url: URL) -> Bool {
        guard detectType(for: url) == .gif else { return false }
        if let metadata = GIFDecoder.metadata(url: url) {
            return metadata.frameCount > 1
        }
        return false
    }
}
