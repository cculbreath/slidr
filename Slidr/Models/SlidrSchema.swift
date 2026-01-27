import SwiftData
import SwiftUI
import Foundation
import CoreGraphics

// MARK: - Schema V1 (Pre-UI Overhaul)

enum SlidrSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MediaItem.self, Playlist.self, AppSettings.self]
    }

    @Model
    final class MediaItem {
        @Attribute(.unique) var id: UUID
        var contentHash: String
        var originalFilename: String
        var relativePath: String
        var storageLocation: StorageLocation
        var fileSize: Int64
        var importDate: Date
        var fileModifiedDate: Date
        var mediaType: MediaType
        var width: Int?
        var height: Int?
        var duration: TimeInterval?
        var frameRate: Double?
        var hasAudio: Bool?
        @Relationship(deleteRule: .nullify)
        var playlists: [SlidrSchemaV1.Playlist]?
        var caption: String?
        var isFavorite: Bool
        var rating: Int?
        var tags: [String]
        var status: MediaStatus
        var lastVerifiedDate: Date?

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
            self.rating = nil
            self.tags = []
            self.lastVerifiedDate = nil
            self.playlists = []
        }
    }

    @Model
    final class Playlist {
        @Attribute(.unique) var id: UUID
        var name: String
        var type: PlaylistType
        var createdDate: Date
        var modifiedDate: Date
        var sortOrder: SortOrder
        var sortAscending: Bool
        @Relationship(deleteRule: .nullify, inverse: \SlidrSchemaV1.MediaItem.playlists)
        var manualItems: [SlidrSchemaV1.MediaItem]?
        var manualItemOrder: [UUID]
        var watchedFolderPath: String?
        var includeSubfolders: Bool
        var filterMinDuration: TimeInterval?
        var filterMaxDuration: TimeInterval?
        var filterMediaTypes: [String]?
        var filterFavoritesOnly: Bool
        var filterMinRating: Int?
        var iconName: String?
        var colorHex: String?

        init(name: String, type: PlaylistType) {
            self.id = UUID()
            self.name = name
            self.type = type
            self.createdDate = Date()
            self.modifiedDate = Date()
            self.sortOrder = .dateImported
            self.sortAscending = false
            self.manualItems = []
            self.manualItemOrder = []
            self.includeSubfolders = true
            self.filterFavoritesOnly = false
            self.filterMinRating = nil
        }
    }

    @Model
    final class AppSettings {
        @Attribute(.unique) var id: UUID
        var showWelcomeOnLaunch: Bool
        var confirmBeforeDelete: Bool
        var defaultSortOrder: SortOrder
        var defaultSortAscending: Bool
        var customLibraryPath: String?
        var copyFilesToLibrary: Bool
        var convertIncompatibleFormats: Bool
        var keepOriginalAfterConversion: Bool
        var skipDuplicates: Bool
        var defaultImportLocation: StorageLocation
        var importTargetFormat: VideoFormat
        var importOrganizeByDate: Bool
        var externalDrivePath: String?
        var defaultThumbnailSize: ThumbnailSize
        var maxMemoryCacheItems: Int
        var maxDiskCacheMB: Int
        var animateGIFsInGrid: Bool
        var defaultImageDuration: TimeInterval
        var defaultGIFDuration: TimeInterval
        var loopSlideshow: Bool
        var shuffleSlideshow: Bool
        var showCaptions: Bool
        var captionTemplate: String
        var captionPosition: CaptionPosition
        var captionFontSize: Double
        var captionBackgroundOpacity: Double
        var slideshowTransition: TransitionType
        var slideshowTransitionDuration: TimeInterval
        var slideshowVideoMode: VideoPlaybackMode
        var useAllMonitors: Bool
        var controlPanelOnSeparateMonitor: Bool
        var preferredControlMonitor: Int?
        var gridShowFilenames: Bool
        // NOTE: no gridShowCaptions in V1
        var gridVideoHoverScrub: Bool
        var verifyFilesOnLaunch: Bool
        var removeOrphanedThumbnails: Bool
        var lastVerificationDate: Date?
        var defaultVolume: Float
        var muteByDefault: Bool

        init() {
            self.id = UUID()
            self.showWelcomeOnLaunch = true
            self.confirmBeforeDelete = true
            self.defaultSortOrder = .dateImported
            self.defaultSortAscending = false
            self.copyFilesToLibrary = true
            self.convertIncompatibleFormats = true
            self.keepOriginalAfterConversion = false
            self.skipDuplicates = true
            self.defaultImportLocation = .local
            self.importTargetFormat = .h264MP4
            self.importOrganizeByDate = false
            self.defaultThumbnailSize = .medium
            self.maxMemoryCacheItems = 100
            self.maxDiskCacheMB = 500
            self.animateGIFsInGrid = false
            self.defaultImageDuration = 5.0
            self.defaultGIFDuration = 10.0
            self.loopSlideshow = true
            self.shuffleSlideshow = false
            self.showCaptions = false
            self.captionTemplate = "{filename}"
            self.captionPosition = .bottom
            self.captionFontSize = 16.0
            self.captionBackgroundOpacity = 0.6
            self.slideshowTransition = .crossfade
            self.slideshowTransitionDuration = 0.5
            self.slideshowVideoMode = .playFull
            self.useAllMonitors = false
            self.controlPanelOnSeparateMonitor = false
            self.gridShowFilenames = false
            self.gridVideoHoverScrub = true
            self.verifyFilesOnLaunch = false
            self.removeOrphanedThumbnails = true
            self.defaultVolume = 1.0
            self.muteByDefault = false
        }
    }
}

// MARK: - Schema V2 (UI Overhaul: added frameCount, gridShowCaptions)

enum SlidrSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MediaItem.self, Playlist.self, AppSettings.self]
    }
}

// MARK: - Migration Plan

enum SlidrMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SlidrSchemaV1.self, SlidrSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV1.self,
        toVersion: SlidrSchemaV2.self
    )
}
