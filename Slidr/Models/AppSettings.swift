import SwiftData
import SwiftUI

@Model
final class AppSettings {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID

    // MARK: - General
    var showWelcomeOnLaunch: Bool
    var confirmBeforeDelete: Bool
    var defaultSortOrder: SortOrder
    var defaultSortAscending: Bool
    var customLibraryPath: String?

    // MARK: - Import
    var importMode: ImportMode
    var convertIncompatibleFormats: Bool
    var keepOriginalAfterConversion: Bool
    var skipDuplicates: Bool
    var defaultImportLocation: StorageLocation
    var importTargetFormat: VideoFormat
    var importOrganizeByDate: Bool
    var createPlaylistsFromFolders: Bool
    var externalDrivePath: String?

    // MARK: - Thumbnails
    var defaultThumbnailSize: ThumbnailSize
    var maxMemoryCacheItems: Int
    var maxDiskCacheMB: Int
    var animateGIFsInGrid: Bool
    var scrubThumbnailCount: Int

    // MARK: - Slideshow
    var defaultImageDuration: TimeInterval
    var defaultGIFDuration: TimeInterval
    var loopSlideshow: Bool
    var shuffleSlideshow: Bool
    var showCaptions: Bool
    var captionTemplate: String
    var captionPosition: CaptionPosition
    var captionDisplayModeRaw: String?
    var captionFontSize: Double
    var captionBackgroundOpacity: Double
    var videoCaptionDurationRaw: Double?
    var slideshowTransition: TransitionType
    var slideshowTransitionDuration: TimeInterval
    var slideshowVideoMode: VideoPlaybackMode
    var videoPlayDurationTag: String
    var videoPlayDurationSeconds: Double
    var randomizeClipLocation: Bool
    var playFullGIF: Bool
    var showTimerBarRaw: Bool?

    // MARK: - Multi-Monitor
    var useAllMonitors: Bool
    var controlPanelOnSeparateMonitor: Bool
    var preferredControlMonitor: Int?

    // MARK: - Grid
    var gridShowFilenames: Bool
    var gridShowCaptionsRaw: Bool?
    var gridVideoHoverScrub: Bool
    var gridMediaTypeFilterRaw: String?

    var gridShowCaptions: Bool {
        get { gridShowCaptionsRaw ?? true }
        set { gridShowCaptionsRaw = newValue }
    }

    var gridMediaTypeFilter: Set<MediaType> {
        get {
            guard let raw = gridMediaTypeFilterRaw else { return [] }
            let types = raw.split(separator: ",").compactMap { MediaType(rawValue: String($0)) }
            return Set(types)
        }
        set {
            if newValue.isEmpty {
                gridMediaTypeFilterRaw = nil
            } else {
                gridMediaTypeFilterRaw = newValue.map(\.rawValue).sorted().joined(separator: ",")
            }
        }
    }

    var captionDisplayMode: CaptionDisplayMode {
        get { captionDisplayModeRaw.flatMap { CaptionDisplayMode(rawValue: $0) } ?? .overlay }
        set { captionDisplayModeRaw = newValue.rawValue }
    }

    var videoCaptionDuration: Double {
        get { videoCaptionDurationRaw ?? 5.0 }
        set { videoCaptionDurationRaw = newValue }
    }

    var showTimerBar: Bool {
        get { showTimerBarRaw ?? false }
        set { showTimerBarRaw = newValue }
    }

    // MARK: - Verification
    var verifyFilesOnLaunch: Bool
    var removeOrphanedThumbnails: Bool
    var lastVerificationDate: Date?

    // MARK: - Audio
    var defaultVolume: Float
    var muteByDefault: Bool

    // MARK: - Initialization
    init() {
        self.id = UUID()

        // General defaults
        self.showWelcomeOnLaunch = true
        self.confirmBeforeDelete = true
        self.defaultSortOrder = .dateImported
        self.defaultSortAscending = false
        self.customLibraryPath = nil

        // Import defaults
        self.importMode = .copy
        self.convertIncompatibleFormats = true
        self.keepOriginalAfterConversion = false
        self.skipDuplicates = true
        self.defaultImportLocation = .local
        self.importTargetFormat = .h264MP4
        self.importOrganizeByDate = false
        self.createPlaylistsFromFolders = false
        self.externalDrivePath = nil

        // Thumbnail defaults
        self.defaultThumbnailSize = .medium
        self.maxMemoryCacheItems = 100
        self.maxDiskCacheMB = 500
        self.animateGIFsInGrid = false
        self.scrubThumbnailCount = 100

        // Slideshow defaults
        self.defaultImageDuration = 5.0
        self.defaultGIFDuration = 10.0
        self.loopSlideshow = true
        self.shuffleSlideshow = false
        self.showCaptions = false
        self.captionTemplate = "{filename}"
        self.captionPosition = .bottom
        self.captionDisplayModeRaw = CaptionDisplayMode.overlay.rawValue
        self.captionFontSize = 16.0
        self.captionBackgroundOpacity = 0.6
        self.videoCaptionDurationRaw = 5.0
        self.slideshowTransition = .crossfade
        self.slideshowTransitionDuration = 0.5
        self.slideshowVideoMode = .playFull
        self.videoPlayDurationTag = "fixed"
        self.videoPlayDurationSeconds = 30
        self.randomizeClipLocation = false
        self.playFullGIF = false
        self.showTimerBarRaw = false

        // Multi-monitor defaults
        self.useAllMonitors = false
        self.controlPanelOnSeparateMonitor = false
        self.preferredControlMonitor = nil

        // Grid defaults
        self.gridShowFilenames = false
        self.gridShowCaptionsRaw = true
        self.gridVideoHoverScrub = true
        self.gridMediaTypeFilterRaw = nil

        // Verification defaults
        self.verifyFilesOnLaunch = false
        self.removeOrphanedThumbnails = true
        self.lastVerificationDate = nil

        // Audio defaults
        self.defaultVolume = 1.0
        self.muteByDefault = false
    }

    // MARK: - Computed Properties

    var videoPlayDuration: VideoPlayDuration {
        get {
            switch videoPlayDurationTag {
            case "slideshowTimer": return .slideshowTimer
            case "fullVideo": return .fullVideo
            case "fixed": return .fixed(videoPlayDurationSeconds)
            default: return .fixed(30)
            }
        }
        set {
            switch newValue {
            case .slideshowTimer:
                videoPlayDurationTag = "slideshowTimer"
            case .fullVideo:
                videoPlayDurationTag = "fullVideo"
            case .fixed(let seconds):
                videoPlayDurationTag = "fixed"
                videoPlayDurationSeconds = seconds
            }
        }
    }

    var resolvedLibraryPath: URL {
        if let custom = customLibraryPath {
            return URL(fileURLWithPath: custom)
        }
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/Slidr/Library", isDirectory: true)
        }
        return appSupport.appendingPathComponent("Slidr/Library", isDirectory: true)
    }
}
