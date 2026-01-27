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
    var copyFilesToLibrary: Bool
    var convertIncompatibleFormats: Bool
    var keepOriginalAfterConversion: Bool
    var skipDuplicates: Bool
    var defaultImportLocation: StorageLocation

    // MARK: - Thumbnails
    var defaultThumbnailSize: ThumbnailSize
    var maxMemoryCacheItems: Int
    var maxDiskCacheMB: Int
    var animateGIFsInGrid: Bool

    // MARK: - Slideshow
    var defaultImageDuration: TimeInterval
    var defaultGIFDuration: TimeInterval
    var loopSlideshow: Bool
    var shuffleSlideshow: Bool
    var showCaptions: Bool
    var captionTemplate: String
    var captionPosition: CaptionPosition
    var captionFontSize: Double

    // MARK: - Multi-Monitor
    var useAllMonitors: Bool
    var controlPanelOnSeparateMonitor: Bool
    var preferredControlMonitor: Int?

    // MARK: - Grid
    var gridShowFilenames: Bool
    var gridVideoHoverScrub: Bool

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
        self.copyFilesToLibrary = true
        self.convertIncompatibleFormats = true
        self.keepOriginalAfterConversion = false
        self.skipDuplicates = true
        self.defaultImportLocation = .local

        // Thumbnail defaults
        self.defaultThumbnailSize = .medium
        self.maxMemoryCacheItems = 100
        self.maxDiskCacheMB = 500
        self.animateGIFsInGrid = false

        // Slideshow defaults
        self.defaultImageDuration = 5.0
        self.defaultGIFDuration = 10.0
        self.loopSlideshow = true
        self.shuffleSlideshow = false
        self.showCaptions = false
        self.captionTemplate = "{filename}"
        self.captionPosition = .bottom
        self.captionFontSize = 16.0

        // Multi-monitor defaults
        self.useAllMonitors = false
        self.controlPanelOnSeparateMonitor = false
        self.preferredControlMonitor = nil

        // Grid defaults
        self.gridShowFilenames = false
        self.gridVideoHoverScrub = true

        // Verification defaults
        self.verifyFilesOnLaunch = false
        self.removeOrphanedThumbnails = true
        self.lastVerificationDate = nil

        // Audio defaults
        self.defaultVolume = 1.0
        self.muteByDefault = false
    }

    // MARK: - Computed Properties

    var resolvedLibraryPath: URL {
        if let custom = customLibraryPath {
            return URL(fileURLWithPath: custom)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Slidr/Library", isDirectory: true)
    }
}

// MARK: - Caption Position Enum

enum CaptionPosition: String, Codable, CaseIterable {
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var alignment: Alignment {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}
