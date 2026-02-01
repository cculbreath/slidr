/// SlidrSchemaV11 — Frozen schema snapshot
/// Adds: summary (String?) to MediaItem for AI-generated descriptions

import SwiftData
import SwiftUI
import Foundation

enum SlidrSchemaV11: VersionedSchema {
    static var versionIdentifier = Schema.Version(11, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SlidrSchemaV11.MediaItem.self, SlidrSchemaV11.Playlist.self, SlidrSchemaV11.AppSettings.self]
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
        var frameCount: Int?
        @Relationship(deleteRule: .nullify)
        var playlists: [SlidrSchemaV11.Playlist]?
        var caption: String?
        var isFavorite: Bool
        var rating: Int?
        var tags: [String]
        var status: MediaStatus
        var hasThumbnailErrorRaw: Bool?
        var hasDecodeErrorRaw: Bool?
        var lastVerifiedDate: Date?
        var source: String?
        var production: ProductionType?
        var transcriptText: String?
        var transcriptRelativePath: String?
        var summary: String?

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
        @Relationship(deleteRule: .nullify, inverse: \SlidrSchemaV11.MediaItem.playlists)
        var manualItems: [SlidrSchemaV11.MediaItem]?
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
        var importMode: ImportMode
        var convertIncompatibleFormats: Bool
        var keepOriginalAfterConversion: Bool
        var skipDuplicates: Bool
        var defaultImportLocation: StorageLocation
        var importTargetFormat: VideoFormat
        var importOrganizeByDate: Bool
        var createPlaylistsFromFolders: Bool
        var externalDrivePath: String?
        var defaultThumbnailSize: ThumbnailSize
        var maxMemoryCacheItems: Int
        var maxDiskCacheMB: Int
        var animateGIFsInGrid: Bool
        var scrubThumbnailCount: Int
        var defaultImageDuration: TimeInterval
        var defaultGIFDuration: TimeInterval
        var loopSlideshow: Bool
        var shuffleSlideshow: Bool
        var showCaptions: Bool
        var captionTemplate: String
        var captionPosition: CaptionPosition
        var captionFontSize: Double
        var captionBackgroundOpacity: Double
        var captionDisplayModeRaw: String?
        var videoCaptionDurationRaw: Double?
        var slideshowTransition: TransitionType
        var slideshowTransitionDuration: TimeInterval
        var slideshowVideoMode: VideoPlaybackMode
        var videoPlayDurationTag: String
        var videoPlayDurationSeconds: Double
        var randomizeClipLocation: Bool
        var playFullGIF: Bool
        var showTimerBarRaw: Bool?
        var showSubtitlesRaw: Bool?
        var subtitlePositionRaw: String?
        var subtitleFontSizeRaw: Double?
        var subtitleOpacityRaw: Double?
        var useAllMonitors: Bool
        var controlPanelOnSeparateMonitor: Bool
        var preferredControlMonitor: Int?
        var gridShowFilenames: Bool
        var gridShowCaptionsRaw: Bool?
        var gridVideoHoverScrub: Bool
        var gridMediaTypeFilterRaw: String?
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
            self.importMode = .copy
            self.convertIncompatibleFormats = true
            self.keepOriginalAfterConversion = false
            self.skipDuplicates = true
            self.defaultImportLocation = .local
            self.importTargetFormat = .h264MP4
            self.importOrganizeByDate = false
            self.createPlaylistsFromFolders = false
            self.defaultThumbnailSize = .medium
            self.maxMemoryCacheItems = 100
            self.maxDiskCacheMB = 500
            self.animateGIFsInGrid = false
            self.scrubThumbnailCount = 100
            self.defaultImageDuration = 5.0
            self.defaultGIFDuration = 10.0
            self.loopSlideshow = true
            self.shuffleSlideshow = false
            self.showCaptions = false
            self.captionTemplate = "{filename}"
            self.captionPosition = .bottom
            self.captionFontSize = 16.0
            self.captionBackgroundOpacity = 0.6
            self.captionDisplayModeRaw = CaptionDisplayMode.overlay.rawValue
            self.videoCaptionDurationRaw = 5.0
            self.slideshowTransition = .crossfade
            self.slideshowTransitionDuration = 0.5
            self.slideshowVideoMode = .playFull
            self.videoPlayDurationTag = "fixed"
            self.videoPlayDurationSeconds = 30
            self.randomizeClipLocation = false
            self.playFullGIF = false
            self.showTimerBarRaw = false
            self.showSubtitlesRaw = false
            self.subtitlePositionRaw = CaptionPosition.bottom.rawValue
            self.subtitleFontSizeRaw = 16.0
            self.subtitleOpacityRaw = 0.7
            self.useAllMonitors = false
            self.controlPanelOnSeparateMonitor = false
            self.gridShowFilenames = false
            self.gridShowCaptionsRaw = true
            self.gridVideoHoverScrub = true
            self.gridMediaTypeFilterRaw = nil
            self.verifyFilesOnLaunch = false
            self.removeOrphanedThumbnails = true
            self.defaultVolume = 1.0
            self.muteByDefault = false
        }
    }
}
