import SwiftData
import SwiftUI
import Foundation
import CoreGraphics

// MARK: - Schema V1 (Pre-UI Overhaul)
// Historical schema - databases created before the UI overhaul

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

// MARK: - Schema V2 (UI Overhaul)
// Explicit snapshot of the database schema as it exists in production.
// Added: frameCount, importMode (replaced copyFilesToLibrary), gridShowCaptionsRaw,
// scrubThumbnailCount, createPlaylistsFromFolders, playFullGIF, videoPlayDuration fields, etc.
// Does NOT include: hasThumbnailError, captionDisplayMode, videoCaptionDuration (added in V3)

enum SlidrSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

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
        var frameCount: Int?
        @Relationship(deleteRule: .nullify)
        var playlists: [SlidrSchemaV2.Playlist]?
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
        @Relationship(deleteRule: .nullify, inverse: \SlidrSchemaV2.MediaItem.playlists)
        var manualItems: [SlidrSchemaV2.MediaItem]?
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
        var slideshowTransition: TransitionType
        var slideshowTransitionDuration: TimeInterval
        var slideshowVideoMode: VideoPlaybackMode
        var videoPlayDurationTag: String
        var videoPlayDurationSeconds: Double
        var randomizeClipLocation: Bool
        var playFullGIF: Bool
        var useAllMonitors: Bool
        var controlPanelOnSeparateMonitor: Bool
        var preferredControlMonitor: Int?
        var gridShowFilenames: Bool
        var gridShowCaptionsRaw: Bool?
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
            self.slideshowTransition = .crossfade
            self.slideshowTransitionDuration = 0.5
            self.slideshowVideoMode = .playFull
            self.videoPlayDurationTag = "fixed"
            self.videoPlayDurationSeconds = 30
            self.randomizeClipLocation = false
            self.playFullGIF = false
            self.useAllMonitors = false
            self.controlPanelOnSeparateMonitor = false
            self.gridShowFilenames = false
            self.gridShowCaptionsRaw = true
            self.gridVideoHoverScrub = true
            self.verifyFilesOnLaunch = false
            self.removeOrphanedThumbnails = true
            self.defaultVolume = 1.0
            self.muteByDefault = false
        }
    }
}

// MARK: - Schema V3
// Adds: hasThumbnailError to MediaItem, captionDisplayMode and videoCaptionDuration to AppSettings
// Snapshot of schema before source attribute was added

enum SlidrSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SlidrSchemaV3.MediaItem.self, SlidrSchemaV3.Playlist.self, SlidrSchemaV3.AppSettings.self]
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
        var playlists: [SlidrSchemaV3.Playlist]?
        var caption: String?
        var isFavorite: Bool
        var rating: Int?
        var tags: [String]
        var status: MediaStatus
        var hasThumbnailErrorRaw: Bool?
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
        @Relationship(deleteRule: .nullify, inverse: \SlidrSchemaV3.MediaItem.playlists)
        var manualItems: [SlidrSchemaV3.MediaItem]?
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
        var useAllMonitors: Bool
        var controlPanelOnSeparateMonitor: Bool
        var preferredControlMonitor: Int?
        var gridShowFilenames: Bool
        var gridShowCaptionsRaw: Bool?
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
            self.useAllMonitors = false
            self.controlPanelOnSeparateMonitor = false
            self.gridShowFilenames = false
            self.gridShowCaptionsRaw = true
            self.gridVideoHoverScrub = true
            self.verifyFilesOnLaunch = false
            self.removeOrphanedThumbnails = true
            self.defaultVolume = 1.0
            self.muteByDefault = false
        }
    }
}

// MARK: - Schema V4
// Adds: source to MediaItem for tracking media origin/attribution
// Snapshot of schema before gridMediaTypeFilterRaw was added

enum SlidrSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SlidrSchemaV4.MediaItem.self, SlidrSchemaV4.Playlist.self, SlidrSchemaV4.AppSettings.self]
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
        var playlists: [SlidrSchemaV4.Playlist]?
        var caption: String?
        var isFavorite: Bool
        var rating: Int?
        var tags: [String]
        var status: MediaStatus
        var hasThumbnailErrorRaw: Bool?
        var lastVerifiedDate: Date?
        var source: String?

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
        @Relationship(deleteRule: .nullify, inverse: \SlidrSchemaV4.MediaItem.playlists)
        var manualItems: [SlidrSchemaV4.MediaItem]?
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
        var useAllMonitors: Bool
        var controlPanelOnSeparateMonitor: Bool
        var preferredControlMonitor: Int?
        var gridShowFilenames: Bool
        var gridShowCaptionsRaw: Bool?
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
            self.useAllMonitors = false
            self.controlPanelOnSeparateMonitor = false
            self.gridShowFilenames = false
            self.gridShowCaptionsRaw = true
            self.gridVideoHoverScrub = true
            self.verifyFilesOnLaunch = false
            self.removeOrphanedThumbnails = true
            self.defaultVolume = 1.0
            self.muteByDefault = false
        }
    }
}

// MARK: - Schema V5
// Adds: gridMediaTypeFilterRaw to AppSettings for persisting media type filter
// Snapshot before showTimerBarRaw was added

enum SlidrSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SlidrSchemaV5.MediaItem.self, SlidrSchemaV5.Playlist.self, SlidrSchemaV5.AppSettings.self]
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
        var playlists: [SlidrSchemaV5.Playlist]?
        var caption: String?
        var isFavorite: Bool
        var rating: Int?
        var tags: [String]
        var status: MediaStatus
        var hasThumbnailErrorRaw: Bool?
        var lastVerifiedDate: Date?
        var source: String?

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
        @Relationship(deleteRule: .nullify, inverse: \SlidrSchemaV5.MediaItem.playlists)
        var manualItems: [SlidrSchemaV5.MediaItem]?
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

// MARK: - Schema V6
// Adds: showTimerBarRaw to AppSettings for persisting timer bar visibility
// Snapshot before production field was added to MediaItem

enum SlidrSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SlidrSchemaV6.MediaItem.self, SlidrSchemaV6.Playlist.self, SlidrSchemaV6.AppSettings.self]
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
        var playlists: [SlidrSchemaV6.Playlist]?
        var caption: String?
        var isFavorite: Bool
        var rating: Int?
        var tags: [String]
        var status: MediaStatus
        var hasThumbnailErrorRaw: Bool?
        var lastVerifiedDate: Date?
        var source: String?

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
        @Relationship(deleteRule: .nullify, inverse: \SlidrSchemaV6.MediaItem.playlists)
        var manualItems: [SlidrSchemaV6.MediaItem]?
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

// MARK: - Schema V7
// Adds: production (ProductionType?) to MediaItem for categorizing content origin
// Snapshot frozen before transcript fields were added to MediaItem

enum SlidrSchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SlidrSchemaV7.MediaItem.self, SlidrSchemaV7.Playlist.self, SlidrSchemaV7.AppSettings.self]
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
        var playlists: [SlidrSchemaV7.Playlist]?
        var caption: String?
        var isFavorite: Bool
        var rating: Int?
        var tags: [String]
        var status: MediaStatus
        var hasThumbnailErrorRaw: Bool?
        var lastVerifiedDate: Date?
        var source: String?
        var production: ProductionType?

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
        @Relationship(deleteRule: .nullify, inverse: \SlidrSchemaV7.MediaItem.playlists)
        var manualItems: [SlidrSchemaV7.MediaItem]?
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

// MARK: - Schema V8 (Current)
// Adds: transcriptText, transcriptRelativePath to MediaItem for subtitle support
// This schema uses the live model definitions.

enum SlidrSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MediaItem.self, Playlist.self, AppSettings.self]
    }
}

// MARK: - Migration Plan

enum SlidrMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SlidrSchemaV1.self, SlidrSchemaV2.self, SlidrSchemaV3.self, SlidrSchemaV4.self, SlidrSchemaV5.self, SlidrSchemaV6.self, SlidrSchemaV7.self, SlidrSchemaV8.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7, migrateV7toV8]
    }

    // V1 -> V2: Custom migration to handle copyFilesToLibrary -> importMode conversion
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SlidrSchemaV1.self,
        toVersion: SlidrSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            // After schema migration, convert copyFilesToLibrary boolean to importMode enum
            let fetchDescriptor = FetchDescriptor<SlidrSchemaV2.AppSettings>()
            let settings = try context.fetch(fetchDescriptor)
            for setting in settings {
                // New databases will have importMode set; for migrated ones, default to .copy
                // The old copyFilesToLibrary=true maps to .copy, false maps to .reference
                // Since we can't read the old value after migration, default to .copy
                if setting.importMode.rawValue.isEmpty {
                    setting.importMode = .copy
                }
            }
            try context.save()
        }
    )

    // V2 -> V3: Lightweight migration for new optional fields with defaults
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV2.self,
        toVersion: SlidrSchemaV3.self
    )

    // V3 -> V4: Lightweight migration for new source field on MediaItem
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV3.self,
        toVersion: SlidrSchemaV4.self
    )

    // V4 -> V5: Lightweight migration for new gridMediaTypeFilterRaw on AppSettings
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV4.self,
        toVersion: SlidrSchemaV5.self
    )

    // V5 -> V6: Lightweight migration for new showTimerBarRaw on AppSettings
    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV5.self,
        toVersion: SlidrSchemaV6.self
    )

    // V6 -> V7: Lightweight migration for new production field on MediaItem
    static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV6.self,
        toVersion: SlidrSchemaV7.self
    )

    // V7 -> V8: Lightweight migration for new transcript fields on MediaItem
    static let migrateV7toV8 = MigrationStage.lightweight(
        fromVersion: SlidrSchemaV7.self,
        toVersion: SlidrSchemaV8.self
    )
}
