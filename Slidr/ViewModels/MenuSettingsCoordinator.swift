import SwiftUI

@MainActor
@Observable
final class MenuSettingsCoordinator {
    private var settings: AppSettings?
    private var gridViewModel: GridViewModel?

    // MARK: - Import

    var importDestination: StorageLocation = .local {
        didSet { settings?.defaultImportLocation = importDestination }
    }

    // MARK: - Grid Display

    var gridShowFilenames: Bool = false {
        didSet { settings?.gridShowFilenames = gridShowFilenames }
    }

    var gridShowCaptions: Bool = true {
        didSet { settings?.gridShowCaptions = gridShowCaptions }
    }

    var animateGIFs: Bool = false {
        didSet { settings?.animateGIFsInGrid = animateGIFs }
    }

    var videoHoverScrub: Bool = true {
        didSet { settings?.gridVideoHoverScrub = videoHoverScrub }
    }

    var browserViewMode: BrowserViewMode = .grid {
        didSet {
            settings?.browserViewMode = browserViewMode
            gridViewModel?.browserMode = browserViewMode
        }
    }

    // MARK: - Slideshow

    var loopSlideshow: Bool = true {
        didSet { settings?.loopSlideshow = loopSlideshow }
    }

    var shuffleSlideshow: Bool = false {
        didSet { settings?.shuffleSlideshow = shuffleSlideshow }
    }

    var slideshowTransition: TransitionType = .crossfade {
        didSet { settings?.slideshowTransition = slideshowTransition }
    }

    var slideDuration: Double = 5.0 {
        didSet { settings?.defaultImageDuration = slideDuration }
    }

    var playFullGIF: Bool = false {
        didSet { settings?.playFullGIF = playFullGIF }
    }

    var videoPlayDuration: VideoPlayDuration = .fixed(30) {
        didSet { settings?.videoPlayDuration = videoPlayDuration }
    }

    var showTimerBar: Bool = false {
        didSet { settings?.showTimerBar = showTimerBar }
    }

    var showSlideshowCaptions: Bool = false {
        didSet { settings?.showCaptions = showSlideshowCaptions }
    }

    // MARK: - Subtitles

    var showSubtitles: Bool = false {
        didSet { settings?.showSubtitles = showSubtitles }
    }

    var subtitlePosition: CaptionPosition = .bottom {
        didSet { settings?.subtitlePosition = subtitlePosition }
    }

    var subtitleFontSize: Double = 16.0 {
        didSet { settings?.subtitleFontSize = subtitleFontSize }
    }

    var subtitleOpacity: Double = 0.7 {
        didSet { settings?.subtitleOpacity = subtitleOpacity }
    }

    // MARK: - AI

    var aiAutoProcess: Bool = false {
        didSet { settings?.aiAutoProcessOnImport = aiAutoProcess }
    }

    var aiAutoTranscribe: Bool = false {
        didSet { settings?.aiAutoTranscribeOnImport = aiAutoTranscribe }
    }

    var aiTagMode: AITagMode = .generateNew {
        didSet { settings?.aiTagMode = aiTagMode }
    }

    // MARK: - Loading

    func load(from settings: AppSettings, gridViewModel: GridViewModel) {
        // Disconnect to prevent write-back during bulk assignment
        self.settings = nil
        self.gridViewModel = nil

        importDestination = settings.defaultImportLocation
        gridShowFilenames = settings.gridShowFilenames
        gridShowCaptions = settings.gridShowCaptions
        animateGIFs = settings.animateGIFsInGrid
        videoHoverScrub = settings.gridVideoHoverScrub
        browserViewMode = settings.browserViewMode
        loopSlideshow = settings.loopSlideshow
        shuffleSlideshow = settings.shuffleSlideshow
        slideshowTransition = settings.slideshowTransition
        showSubtitles = settings.showSubtitles
        subtitlePosition = settings.subtitlePosition
        subtitleFontSize = settings.subtitleFontSize
        subtitleOpacity = settings.subtitleOpacity
        slideDuration = settings.defaultImageDuration
        playFullGIF = settings.playFullGIF
        videoPlayDuration = settings.videoPlayDuration
        showTimerBar = settings.showTimerBar
        showSlideshowCaptions = settings.showCaptions
        aiAutoProcess = settings.aiAutoProcessOnImport
        aiAutoTranscribe = settings.aiAutoTranscribeOnImport
        aiTagMode = settings.aiTagMode

        // Reconnect for future didSet write-backs
        self.settings = settings
        self.gridViewModel = gridViewModel
    }
}
