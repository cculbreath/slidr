import Foundation
import CoreGraphics

/// Sendable value snapshot of a `MediaItem` for cross-actor use.
///
/// SwiftData `@Model` instances are tied to their model context's actor (the
/// main actor for our setup) and reading their persisted properties off-actor
/// is illegal — it traps outright if the item has been deleted. Convert to
/// this snapshot on the main actor, then pass freely.
struct MediaItemSnapshot: Sendable, Identifiable, Hashable {
    let id: UUID
    let contentHash: String
    let relativePath: String
    let filename: String
    let mediaType: MediaType
    let storageLocation: StorageLocation
    let fileSize: Int64
    let importDate: Date
    let width: Int?
    let height: Int?
    let duration: TimeInterval?
    let rating: Int?
    let tagsCount: Int

    var isVideo: Bool { mediaType == .video }
    var isAnimated: Bool { mediaType == .gif }
    var isRated: Bool { (rating ?? 0) > 0 }
    var dimensions: CGSize? {
        guard let w = width, let h = height else { return nil }
        return CGSize(width: w, height: h)
    }
    var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
    var ratingStars: String {
        let filled = max(0, min(5, rating ?? 0))
        return String(repeating: "\u{2605}", count: filled) + String(repeating: "\u{2606}", count: 5 - filled)
    }

    @MainActor
    static func capture(_ item: MediaItem) -> MediaItemSnapshot {
        MediaItemSnapshot(
            id: item.id,
            contentHash: item.contentHash,
            relativePath: item.relativePath,
            filename: item.originalFilename,
            mediaType: item.mediaType,
            storageLocation: item.storageLocation,
            fileSize: item.fileSize,
            importDate: item.importDate,
            width: item.width,
            height: item.height,
            duration: item.duration,
            rating: item.rating,
            tagsCount: item.tags.count
        )
    }
}
