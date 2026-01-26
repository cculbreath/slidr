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

    // MARK: - User Data
    var isFavorite: Bool

    // MARK: - Status
    var status: MediaStatus

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
        self.isFavorite = false
    }

    // MARK: - Computed Properties
    var dimensions: CGSize? {
        guard let w = width, let h = height else { return nil }
        return CGSize(width: w, height: h)
    }
}
