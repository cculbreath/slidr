import SwiftUI

// MARK: - Action Command Keys

struct StartSlideshowKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct SelectAllKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DeselectAllKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DeleteSelectedKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ToggleInspectorKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ImportFilesKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ImportSubtitlesKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct LocateExternalLibraryKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NewPlaylistKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct NewSmartPlaylistKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FocusSearchKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct IncreaseThumbnailSizeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct DecreaseThumbnailSizeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ResetThumbnailSizeKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct RevealInFinderKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct QuickLookKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowAdvancedFilterKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ClearAllFiltersKey: FocusedValueKey {
    typealias Value = () -> Void
}

// MARK: - Filter Binding Keys

struct MediaTypeFilterBindingKey: FocusedValueKey {
    typealias Value = Binding<Set<MediaType>>
}

struct ProductionTypeFilterBindingKey: FocusedValueKey {
    typealias Value = Binding<Set<ProductionType>>
}

struct SubtitleFilterBindingKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct CaptionFilterBindingKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct RatingFilterEnabledBindingKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct RatingFilterBindingKey: FocusedValueKey {
    typealias Value = Binding<Set<Int>>
}

struct TagFilterBindingKey: FocusedValueKey {
    typealias Value = Binding<Set<String>>
}

struct SortOrderBindingKey: FocusedValueKey {
    typealias Value = Binding<SortOrder>
}

struct SortAscendingBindingKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct AllTagsKey: FocusedValueKey {
    typealias Value = [String]
}

// MARK: - Binding Keys (moved from AppDelegate)

struct ImportDestinationKey: FocusedValueKey {
    typealias Value = Binding<StorageLocation>
}

struct GridFilenamesKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct GridCaptionsKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct AnimateGIFsKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct SubtitleShowKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct SubtitlePositionKey: FocusedValueKey {
    typealias Value = Binding<CaptionPosition>
}

struct SubtitleFontSizeKey: FocusedValueKey {
    typealias Value = Binding<Double>
}

struct SubtitleOpacityKey: FocusedValueKey {
    typealias Value = Binding<Double>
}

// MARK: - FocusedValues Extension

extension FocusedValues {
    // Action commands
    var startSlideshow: (() -> Void)? {
        get { self[StartSlideshowKey.self] }
        set { self[StartSlideshowKey.self] = newValue }
    }

    var selectAll: (() -> Void)? {
        get { self[SelectAllKey.self] }
        set { self[SelectAllKey.self] = newValue }
    }

    var deselectAll: (() -> Void)? {
        get { self[DeselectAllKey.self] }
        set { self[DeselectAllKey.self] = newValue }
    }

    var deleteSelected: (() -> Void)? {
        get { self[DeleteSelectedKey.self] }
        set { self[DeleteSelectedKey.self] = newValue }
    }

    var toggleInspector: (() -> Void)? {
        get { self[ToggleInspectorKey.self] }
        set { self[ToggleInspectorKey.self] = newValue }
    }

    var importFilesAction: (() -> Void)? {
        get { self[ImportFilesKey.self] }
        set { self[ImportFilesKey.self] = newValue }
    }

    var importSubtitlesAction: (() -> Void)? {
        get { self[ImportSubtitlesKey.self] }
        set { self[ImportSubtitlesKey.self] = newValue }
    }

    var locateExternalLibrary: (() -> Void)? {
        get { self[LocateExternalLibraryKey.self] }
        set { self[LocateExternalLibraryKey.self] = newValue }
    }

    var newPlaylist: (() -> Void)? {
        get { self[NewPlaylistKey.self] }
        set { self[NewPlaylistKey.self] = newValue }
    }

    var newSmartPlaylist: (() -> Void)? {
        get { self[NewSmartPlaylistKey.self] }
        set { self[NewSmartPlaylistKey.self] = newValue }
    }

    var focusSearch: (() -> Void)? {
        get { self[FocusSearchKey.self] }
        set { self[FocusSearchKey.self] = newValue }
    }

    var increaseThumbnailSize: (() -> Void)? {
        get { self[IncreaseThumbnailSizeKey.self] }
        set { self[IncreaseThumbnailSizeKey.self] = newValue }
    }

    var decreaseThumbnailSize: (() -> Void)? {
        get { self[DecreaseThumbnailSizeKey.self] }
        set { self[DecreaseThumbnailSizeKey.self] = newValue }
    }

    var resetThumbnailSize: (() -> Void)? {
        get { self[ResetThumbnailSizeKey.self] }
        set { self[ResetThumbnailSizeKey.self] = newValue }
    }

    var revealInFinder: (() -> Void)? {
        get { self[RevealInFinderKey.self] }
        set { self[RevealInFinderKey.self] = newValue }
    }

    var quickLook: (() -> Void)? {
        get { self[QuickLookKey.self] }
        set { self[QuickLookKey.self] = newValue }
    }

    var showAdvancedFilter: (() -> Void)? {
        get { self[ShowAdvancedFilterKey.self] }
        set { self[ShowAdvancedFilterKey.self] = newValue }
    }

    var clearAllFilters: (() -> Void)? {
        get { self[ClearAllFiltersKey.self] }
        set { self[ClearAllFiltersKey.self] = newValue }
    }

    // Filter binding values
    var mediaTypeFilterBinding: Binding<Set<MediaType>>? {
        get { self[MediaTypeFilterBindingKey.self] }
        set { self[MediaTypeFilterBindingKey.self] = newValue }
    }

    var productionTypeFilterBinding: Binding<Set<ProductionType>>? {
        get { self[ProductionTypeFilterBindingKey.self] }
        set { self[ProductionTypeFilterBindingKey.self] = newValue }
    }

    var subtitleFilterBinding: Binding<Bool>? {
        get { self[SubtitleFilterBindingKey.self] }
        set { self[SubtitleFilterBindingKey.self] = newValue }
    }

    var captionFilterBinding: Binding<Bool>? {
        get { self[CaptionFilterBindingKey.self] }
        set { self[CaptionFilterBindingKey.self] = newValue }
    }

    var ratingFilterEnabledBinding: Binding<Bool>? {
        get { self[RatingFilterEnabledBindingKey.self] }
        set { self[RatingFilterEnabledBindingKey.self] = newValue }
    }

    var ratingFilterBinding: Binding<Set<Int>>? {
        get { self[RatingFilterBindingKey.self] }
        set { self[RatingFilterBindingKey.self] = newValue }
    }

    var tagFilterBinding: Binding<Set<String>>? {
        get { self[TagFilterBindingKey.self] }
        set { self[TagFilterBindingKey.self] = newValue }
    }

    var sortOrderBinding: Binding<SortOrder>? {
        get { self[SortOrderBindingKey.self] }
        set { self[SortOrderBindingKey.self] = newValue }
    }

    var sortAscendingBinding: Binding<Bool>? {
        get { self[SortAscendingBindingKey.self] }
        set { self[SortAscendingBindingKey.self] = newValue }
    }

    var allTags: [String]? {
        get { self[AllTagsKey.self] }
        set { self[AllTagsKey.self] = newValue }
    }

    // Binding values
    var importDestination: Binding<StorageLocation>? {
        get { self[ImportDestinationKey.self] }
        set { self[ImportDestinationKey.self] = newValue }
    }

    var gridShowFilenames: Binding<Bool>? {
        get { self[GridFilenamesKey.self] }
        set { self[GridFilenamesKey.self] = newValue }
    }

    var gridShowCaptions: Binding<Bool>? {
        get { self[GridCaptionsKey.self] }
        set { self[GridCaptionsKey.self] = newValue }
    }

    var animateGIFs: Binding<Bool>? {
        get { self[AnimateGIFsKey.self] }
        set { self[AnimateGIFsKey.self] = newValue }
    }

    var subtitleShow: Binding<Bool>? {
        get { self[SubtitleShowKey.self] }
        set { self[SubtitleShowKey.self] = newValue }
    }

    var subtitlePosition: Binding<CaptionPosition>? {
        get { self[SubtitlePositionKey.self] }
        set { self[SubtitlePositionKey.self] = newValue }
    }

    var subtitleFontSize: Binding<Double>? {
        get { self[SubtitleFontSizeKey.self] }
        set { self[SubtitleFontSizeKey.self] = newValue }
    }

    var subtitleOpacity: Binding<Double>? {
        get { self[SubtitleOpacityKey.self] }
        set { self[SubtitleOpacityKey.self] = newValue }
    }
}
