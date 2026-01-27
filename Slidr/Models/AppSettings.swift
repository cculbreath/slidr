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

        // Audio defaults
        self.defaultVolume = 1.0
        self.muteByDefault = false
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
