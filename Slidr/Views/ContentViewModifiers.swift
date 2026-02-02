import SwiftUI

// MARK: - Action Focused Values

struct ActionFocusedValuesModifier: ViewModifier {
    let toggleInspector: () -> Void
    let importFiles: () -> Void
    let importSubtitles: () -> Void
    let quickLook: () -> Void
    let locateExternalLibrary: () -> Void
    let newPlaylist: () -> Void
    let newSmartPlaylist: () -> Void
    let toggleTagPalette: () -> Void

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.toggleInspector, toggleInspector)
            .focusedSceneValue(\.importFilesAction, importFiles)
            .focusedSceneValue(\.importSubtitlesAction, importSubtitles)
            .focusedSceneValue(\.quickLook, quickLook)
            .focusedSceneValue(\.locateExternalLibrary, locateExternalLibrary)
            .focusedSceneValue(\.newPlaylist, newPlaylist)
            .focusedSceneValue(\.newSmartPlaylist, newSmartPlaylist)
            .focusedSceneValue(\.toggleTagPalette, toggleTagPalette)
    }
}

// MARK: - AI Focused Values

struct AIFocusedValuesModifier: ViewModifier {
    @Bindable var coordinator: MenuSettingsCoordinator
    let processSelected: () -> Void
    let tagSelected: () -> Void
    let summarizeSelected: () -> Void
    let transcribeSelected: () -> Void
    let processUntagged: () -> Void
    let processUntranscribed: () -> Void
    let showStatusWindow: () -> Void

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.aiAutoProcess, $coordinator.aiAutoProcess)
            .focusedSceneValue(\.aiAutoTranscribe, $coordinator.aiAutoTranscribe)
            .focusedSceneValue(\.aiTagMode, $coordinator.aiTagMode)
            .focusedSceneValue(\.aiProcessSelected, processSelected)
            .focusedSceneValue(\.aiTagSelected, tagSelected)
            .focusedSceneValue(\.aiSummarizeSelected, summarizeSelected)
            .focusedSceneValue(\.aiTranscribeSelected, transcribeSelected)
            .focusedSceneValue(\.aiProcessUntagged, processUntagged)
            .focusedSceneValue(\.aiProcessUntranscribed, processUntranscribed)
            .focusedSceneValue(\.aiShowStatusWindow, showStatusWindow)
    }
}

// MARK: - Browser Focused Values

struct BrowserFocusedValuesModifier: ViewModifier {
    @Bindable var coordinator: MenuSettingsCoordinator

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.importDestination, $coordinator.importDestination)
            .focusedSceneValue(\.gridShowFilenames, $coordinator.gridShowFilenames)
            .focusedSceneValue(\.gridShowCaptions, $coordinator.gridShowCaptions)
            .focusedSceneValue(\.animateGIFs, $coordinator.animateGIFs)
            .focusedSceneValue(\.browserViewMode, $coordinator.browserViewMode)
            .focusedSceneValue(\.videoHoverScrub, $coordinator.videoHoverScrub)
    }
}

// MARK: - Slideshow Focused Values

struct SlideshowFocusedValuesModifier: ViewModifier {
    @Bindable var coordinator: MenuSettingsCoordinator

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.loopSlideshow, $coordinator.loopSlideshow)
            .focusedSceneValue(\.shuffleSlideshow, $coordinator.shuffleSlideshow)
            .focusedSceneValue(\.slideshowTransition, $coordinator.slideshowTransition)
            .focusedSceneValue(\.slideDuration, $coordinator.slideDuration)
            .focusedSceneValue(\.playFullGIF, $coordinator.playFullGIF)
            .focusedSceneValue(\.videoPlayDuration, $coordinator.videoPlayDuration)
            .focusedSceneValue(\.showTimerBar, $coordinator.showTimerBar)
            .focusedSceneValue(\.slideshowControlsMode, $coordinator.slideshowControlsMode)
            .focusedSceneValue(\.showSlideshowCaptions, $coordinator.showSlideshowCaptions)
            .focusedSceneValue(\.captionPositionMenu, $coordinator.captionPosition)
            .focusedSceneValue(\.captionFontSizeMenu, $coordinator.captionFontSize)
            .focusedSceneValue(\.captionOpacityMenu, $coordinator.captionOpacity)
            .focusedSceneValue(\.captionDisplayModeMenu, $coordinator.captionDisplayMode)
            .focusedSceneValue(\.subtitleShow, $coordinator.showSubtitles)
            .focusedSceneValue(\.subtitlePosition, $coordinator.subtitlePosition)
            .focusedSceneValue(\.subtitleFontSize, $coordinator.subtitleFontSize)
            .focusedSceneValue(\.subtitleOpacity, $coordinator.subtitleOpacity)
    }
}

// MARK: - Filter Focused Values

struct FilterFocusedValuesModifier: ViewModifier {
    @Bindable var gridViewModel: GridViewModel
    let allTags: [String]

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.mediaTypeFilterBinding, $gridViewModel.mediaTypeFilter)
            .focusedSceneValue(\.productionTypeFilterBinding, $gridViewModel.productionTypeFilter)
            .focusedSceneValue(\.subtitleFilterBinding, $gridViewModel.subtitleFilter)
            .focusedSceneValue(\.captionFilterBinding, $gridViewModel.captionFilter)
            .focusedSceneValue(\.ratingFilterEnabledBinding, $gridViewModel.ratingFilterEnabled)
            .focusedSceneValue(\.ratingFilterBinding, $gridViewModel.ratingFilter)
            .focusedSceneValue(\.tagFilterBinding, $gridViewModel.tagFilter)
            .focusedSceneValue(\.sortOrderBinding, $gridViewModel.sortOrder)
            .focusedSceneValue(\.sortAscendingBinding, $gridViewModel.sortAscending)
            .focusedSceneValue(\.allTags, allTags)
    }
}
