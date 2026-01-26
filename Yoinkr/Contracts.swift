// MARK: - Service Protocols (Agent A implements, Agent B consumes)

/// Contract for media library operations
protocol MediaLibraryProtocol {
    var allItems: [MediaItem] { get }
    var itemCount: Int { get }
    var isLoading: Bool { get }

    func importFiles(urls: [URL]) async throws -> ImportResult
    func delete(_ item: MediaItem)
    func delete(_ items: [MediaItem])
}

/// Contract for thumbnail generation
protocol ThumbnailCacheProtocol {
    func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> NSImage
}

// MARK: - Shared Types (Both agents use)

/// Thumbnail sizes
enum ThumbnailSize: String, Codable, CaseIterable, Sendable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"

    var pixelSize: CGFloat {
        switch self {
        case .small: return 128
        case .medium: return 256
        case .large: return 384
        case .extraLarge: return 512
        }
    }
}
