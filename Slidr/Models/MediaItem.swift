import SwiftData
import Foundation
import CoreGraphics

@Model
final class MediaItem {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID
    var contentHash: String

    // MARK: - File Information
    var originalFilename: String
    var relativePath: String
    var storageLocation: StorageLocation
    var fileSize: Int64
    var importDate: Date
    var fileModifiedDate: Date

    // MARK: - Media Metadata
    var mediaType: MediaType
    var width: Int?
    var height: Int?
    var duration: TimeInterval?      // Video duration in seconds
    var frameRate: Double?           // Video frame rate
    var hasAudio: Bool?              // Whether video has audio track
    var frameCount: Int?             // GIF frame count

    // MARK: - Relationships
    @Relationship(deleteRule: .nullify)
    var playlists: [Playlist]?

    // MARK: - User Data
    var caption: String?
    var title: String?
    var isFavorite: Bool
    var rating: Int?
    var tags: [String]
    var source: String?
    var production: ProductionType?
    var summary: String?

    // MARK: - Transcript
    var transcriptText: String?
    var transcriptRelativePath: String?

    // MARK: - Image Text & Audio Captions
    var imageText: String?
    var audioCaptionRelativePath: String?

    // MARK: - Vision Feature Print (for duplicate detection)
    /// Serialized VNFeaturePrintObservation for the item's thumbnail.
    /// nil until computed by FeaturePrintService.
    var featurePrint: Data?

    /// For videos: JSON-encoded array of per-keyframe `VNFeaturePrintObservation`
    /// blobs (sampled at 5 evenly-spaced points along the duration). Comparison
    /// uses the minimum pairwise distance across all frame combos, which lets us
    /// catch duplicates whose static thumbnail came from a different frame.
    /// nil for images and for items predating this code path.
    var featurePrintFrames: Data?

    // MARK: - Status
    var status: MediaStatus
    var hasThumbnailErrorRaw: Bool?
    var hasDecodeErrorRaw: Bool?

    // MARK: - Verification
    var lastVerifiedDate: Date?

    // MARK: - Initialization
    init(
        originalFilename: String,
        relativePath: String,
        storageLocation: StorageLocation,
        contentHash: String,
        fileSize: Int64,
        mediaType: MediaType,
        fileModifiedDate: Date
    ) {
        self.id = UUID()
        self.originalFilename = originalFilename
        self.relativePath = relativePath
        self.storageLocation = storageLocation
        self.contentHash = contentHash
        self.fileSize = fileSize
        self.mediaType = mediaType
        self.fileModifiedDate = fileModifiedDate
        self.importDate = Date()
        self.status = .available
        self.hasThumbnailErrorRaw = false
        self.isFavorite = false
        self.rating = nil
        self.tags = []
        self.source = nil
        self.production = nil
        self.lastVerifiedDate = nil
        self.playlists = []
    }

    // MARK: - Computed Properties
    var dimensions: CGSize? {
        guard let w = width, let h = height else { return nil }
        return CGSize(width: w, height: h)
    }

    var isVideo: Bool { mediaType == .video }
    var isAnimated: Bool { mediaType == .gif }
    var hasTranscript: Bool { transcriptRelativePath != nil }
    var hasImageText: Bool { !(imageText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    var hasAudioCaption: Bool { audioCaptionRelativePath != nil }

    /// Returns the filename stripped of leading numbers and file extension
    /// e.g., "54526658 Girlfriend.gif" → "Girlfriend"
    var displayName: String {
        var name = originalFilename

        // Strip file extension
        if let dotIndex = name.lastIndex(of: ".") {
            name = String(name[..<dotIndex])
        }

        // Strip leading numbers and whitespace (e.g., "54526658 ")
        if let match = name.firstMatch(of: /^\d+\s+/) {
            name = String(name[match.range.upperBound...])
        }

        return name.isEmpty ? originalFilename : name
    }

    var hasThumbnailError: Bool {
        get { hasThumbnailErrorRaw ?? false }
        set { hasThumbnailErrorRaw = newValue }
    }

    var hasDecodeError: Bool {
        get { hasDecodeErrorRaw ?? false }
        set { hasDecodeErrorRaw = newValue }
    }

    var hasCaption: Bool {
        guard let caption = caption else { return false }
        return !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Returns caption if set, otherwise returns display name (filename without leading number and extension)
    var displayCaption: String {
        if let caption = caption, !caption.isEmpty {
            return caption
        }
        return displayName
    }

    var hasSummary: Bool {
        guard let summary = summary else { return false }
        return !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displaySummary: String {
        summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Rating Computed Properties

    var effectiveRating: Int {
        rating ?? 0
    }

    var isRated: Bool {
        guard let rating else { return false }
        return rating > 0
    }

    var ratingStars: String {
        let filled = effectiveRating
        let empty = 5 - filled
        return String(repeating: "\u{2605}", count: filled) + String(repeating: "\u{2606}", count: empty)
    }

    // MARK: - Tag Methods

    func hasTag(_ tag: String) -> Bool {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tags.contains { $0.lowercased() == normalized }
    }

    func addTag(_ tag: String) {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !hasTag(normalized) else { return }
        tags.append(normalized)
    }

    func removeTag(_ tag: String) {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        tags.removeAll { $0.lowercased() == normalized }
    }

    // MARK: - Source Helpers

    var hasSource: Bool {
        guard let source = source else { return false }
        return !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displaySource: String {
        source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Table Sort Keys

    var mediaTypeSortKey: String { mediaType.rawValue }
    var hasTranscriptSortKey: Int { hasTranscript ? 1 : 0 }
    var isFavoriteSortKey: Int { isFavorite ? 1 : 0 }
    var tagsSortKey: String { tags.joined(separator: ", ") }
    var captionSortKey: String { caption ?? "" }
    var summarySortKey: String { summary ?? "" }
    var durationSortKey: Double { duration ?? -1 }
    var sourceSortKey: String { source ?? "" }
    var productionSortKey: String { production?.rawValue ?? "" }
    var dimensionsSortKey: Int { (width ?? 0) * (height ?? 0) }
    var frameRateSortKey: Double { frameRate ?? -1 }
    var hasAudioSortKey: Int { hasAudio == true ? 1 : (hasAudio == false ? 0 : -1) }
    var frameCountSortKey: Int { frameCount ?? -1 }
    var storageLocationSortKey: String { storageLocation.rawValue }
    var statusSortKey: String { status.rawValue }
}
