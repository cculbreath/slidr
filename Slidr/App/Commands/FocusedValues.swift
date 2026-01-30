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
}
