import SwiftUI
import SwiftData

struct SlideshowView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(\.transcriptStore) private var transcriptStore
    @Bindable var viewModel: SlideshowViewModel
    var onDismiss: () -> Void
    @Query private var settingsQuery: [AppSettings]

    @FocusState private var isFocused: Bool
    @State private var uiState = SlideshowUIState()
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var transcriptCues: [TranscriptCue] = []
    @State private var floatingControlsWindow: SlideshowControlsWindowController?

    private var settings: AppSettings? { settingsQuery.first }
    private var controlsMode: SlideshowControlsMode { settings?.slideshowControlsMode ?? .overlay }

    private enum NavigationDirection {
        case forward, backward
    }

    private var currentTransition: AnyTransition {
        let type = settings?.slideshowTransition ?? .crossfade
        switch navigationDirection {
        case .forward:
            return type.enterTransition
        case .backward:
            return type.exitTransition
        }
    }

    private var transitionDuration: Double {
        settings?.slideshowTransitionDuration ?? 0.5
    }

    private var shouldShowCaptions: Bool {
        guard viewModel.showCaptions else { return false }
        if viewModel.currentItemIsVideo {
            return uiState.showVideoCaptions
        }
        return true
    }

    var body: some View {
        slideshowContent
            .focusable()
            .focused($isFocused)
            .modifier(SlideshowKeyboardModifier(viewModel: viewModel, onDismiss: onDismiss, goNext: goNext, goPrevious: goPrevious))
            .modifier(CaptionKeys(viewModel: viewModel))
            .modifier(RatingKeys(viewModel: viewModel, uiState: uiState))
            .modifier(ExtraNavigationKeys(viewModel: viewModel, uiState: uiState))
            .modifier(SlideshowPersistenceModifier(viewModel: viewModel, uiState: uiState, settings: settings, library: library, startVideoCaptionTimer: startVideoCaptionTimer, loadTranscriptCues: loadTranscriptCues, setFocused: { isFocused = true }))
            .modifier(SlideshowMenuSyncModifier(viewModel: viewModel, settings: settings))
            .modifier(SlideshowUIObserverModifier(uiState: uiState))
    }

    // MARK: - Slideshow Content

    @ViewBuilder
    private var slideshowContent: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    uiState.showControlsTemporarily()
                    isFocused = true
                }

            // Current media
            mediaContent
                .animation(.easeInOut(duration: transitionDuration), value: viewModel.currentIndex)
                .onTapGesture {
                    uiState.showControlsTemporarily()
                    isFocused = true
                }

            // Timer progress bar
            if viewModel.showTimerBar {
                VStack {
                    Spacer()
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        GeometryReader { geo in
                            Rectangle()
                                .fill(.white.opacity(0.3))
                                .frame(width: geo.size.width * timerProgress(at: context.date), height: 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 10)
                    }
                }
                .allowsHitTesting(false)
                .animation(nil, value: viewModel.currentIndex)
            }

            // Subtitle overlay
            if viewModel.showSubtitles && !transcriptCues.isEmpty && viewModel.currentItemIsVideo {
                SubtitleOverlayView(
                    cues: transcriptCues,
                    scrubber: viewModel.scrubber,
                    position: settings?.subtitlePosition ?? .bottom,
                    fontSize: settings?.subtitleFontSize ?? 16,
                    backgroundOpacity: settings?.subtitleOpacity ?? 0.7
                )
                .allowsHitTesting(false)
            }

            // Controls overlay (hidden when using floating controls)
            if uiState.showControls && controlsMode == .overlay {
                SlideshowControlsOverlay(
                    viewModel: viewModel,
                    uiState: uiState,
                    goNext: goNext,
                    goPrevious: goPrevious,
                    onDismiss: onDismiss
                )
            }

            // Info overlay
            if uiState.showInfoOverlay, let item = viewModel.currentItem {
                VStack {
                    HStack {
                        Spacer()
                        InfoOverlayView(
                            item: item,
                            index: viewModel.currentIndex,
                            totalCount: viewModel.activeItems.count
                        )
                    }
                    Spacer()
                }
            }

            // Rating feedback
            if let rating = uiState.ratingFeedback {
                ratingFeedbackOverlay(rating: rating)
            }

            // Random mode indicator
            if viewModel.isRandomMode {
                VStack {
                    HStack {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.top, uiState.showControls ? 60 : 16)
                    Spacer()
                }
            }

            // Scrub mode overlay
            if uiState.isScrubModeActive, viewModel.currentItemIsVideo, !uiState.scrubThumbnails.isEmpty {
                SlideshowScrubModeView(
                    viewModel: viewModel,
                    uiState: uiState
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: uiState.showControls)
        .animation(.easeInOut(duration: 0.2), value: uiState.showInfoOverlay)
        .animation(.easeInOut(duration: 0.15), value: uiState.ratingFeedback)
        .animation(.easeInOut(duration: 0.15), value: uiState.isScrubModeActive)
        .onAppear {
            uiState.showControlsTemporarily()
            setupOptionKeyMonitor()
            updateFloatingControls()
        }
        .onDisappear {
            removeOptionKeyMonitor()
            floatingControlsWindow?.close()
            floatingControlsWindow = nil
        }
        .onChange(of: settings?.slideshowControlsMode) { _, _ in
            updateFloatingControls()
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                if location != uiState.lastMouseLocation {
                    uiState.lastMouseLocation = location
                    uiState.showControlsTemporarily()
                }
            case .ended:
                break
            }
        }
    }

    // MARK: - Media Content

    @ViewBuilder
    private var mediaContent: some View {
        if let item = viewModel.currentItem {
            contentView(for: item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .caption(
                    for: item,
                    show: shouldShowCaptions,
                    template: settings?.captionTemplate ?? "{filename}",
                    position: settings?.captionPosition ?? .bottom,
                    displayMode: settings?.captionDisplayMode ?? .overlay,
                    fontSize: settings?.captionFontSize ?? 16,
                    backgroundOpacity: settings?.captionBackgroundOpacity ?? 0.6
                )
                .id(item.id)
                .transition(currentTransition)
        }
    }

    @ViewBuilder
    private func contentView(for item: MediaItem) -> some View {
        if item.isVideo {
            VideoPlayerView(
                item: item,
                fileURL: library.absoluteURL(for: item),
                isPlaying: $viewModel.isPlaying,
                volume: $viewModel.volume,
                isMuted: $viewModel.isMuted,
                scrubber: viewModel.scrubber,
                onVideoEnded: { viewModel.onVideoEnded() }
            )
        } else if item.isAnimated {
            AsyncAnimatedGIFView(item: item)
        } else {
            AsyncThumbnailImage(item: item, size: .large, contentMode: .fit)
        }
    }

    // MARK: - Rating Feedback

    @ViewBuilder
    private func ratingFeedbackOverlay(rating: Int) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(rating > 0 ? String(repeating: "\u{2605}", count: rating) : "No Rating")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Spacer()
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - Navigation

    private func goNext() {
        navigationDirection = .forward
        viewModel.next()
    }

    private func goPrevious() {
        navigationDirection = .backward
        viewModel.previous()
    }

    // MARK: - Floating Controls

    private func updateFloatingControls() {
        if controlsMode == .floating {
            if floatingControlsWindow == nil {
                floatingControlsWindow = SlideshowControlsWindowController(
                    viewModel: viewModel,
                    uiState: uiState,
                    goNext: goNext,
                    goPrevious: goPrevious,
                    onDismiss: onDismiss
                )
            }
            floatingControlsWindow?.show()
        } else {
            floatingControlsWindow?.close()
            floatingControlsWindow = nil
        }
    }

    // MARK: - Transcript Cues

    private func loadTranscriptCues() {
        transcriptCues = []
        guard let transcriptStore,
              let item = viewModel.currentItem,
              item.hasTranscript,
              let relativePath = item.transcriptRelativePath else { return }

        let contentHash = item.contentHash
        Task {
            do {
                let cues = try await transcriptStore.cues(
                    forContentHash: contentHash,
                    relativePath: relativePath
                )
                transcriptCues = cues
            } catch {
                // Silently fail — subtitles just won't show
            }
        }
    }

    // MARK: - Video Captions

    private func startVideoCaptionTimer() {
        uiState.videoCaptionTask?.cancel()

        guard viewModel.showCaptions else {
            uiState.showVideoCaptions = false
            return
        }

        if viewModel.currentItemIsVideo {
            uiState.showVideoCaptions = true
            let duration = settings?.videoCaptionDuration ?? 5.0
            uiState.videoCaptionTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled {
                    withAnimation {
                        uiState.showVideoCaptions = false
                    }
                }
            }
        } else {
            uiState.showVideoCaptions = true
        }
    }

    // MARK: - Timer

    private func timerProgress(at date: Date) -> Double {
        if !viewModel.isPlaying {
            return viewModel.pausedTimerProgress
        }
        guard let start = viewModel.timerStartDate, viewModel.currentSlideDuration > 0 else {
            return 0
        }
        let elapsed = date.timeIntervalSince(start)
        return max(0, min(1.0, elapsed / viewModel.currentSlideDuration))
    }

    // MARK: - Scrub Mode

    private func setupOptionKeyMonitor() {
        uiState.optionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let optionPressed = event.modifierFlags.contains(.option)

            if optionPressed && !uiState.isScrubModeActive && viewModel.currentItemIsVideo {
                enterScrubMode()
            } else if !optionPressed && uiState.isScrubModeActive {
                exitScrubMode()
            }

            return event
        }
    }

    private func removeOptionKeyMonitor() {
        if let monitor = uiState.optionKeyMonitor {
            NSEvent.removeMonitor(monitor)
            uiState.optionKeyMonitor = nil
        }
    }

    private func enterScrubMode() {
        guard let item = viewModel.currentItem, item.isVideo else { return }

        uiState.wasPlayingBeforeScrub = viewModel.isPlaying
        if viewModel.isPlaying {
            viewModel.togglePlayback()
        }

        uiState.scrubPosition = viewModel.scrubber.progress
        uiState.isScrubModeActive = true

        Task {
            let count = settings?.scrubThumbnailCount ?? 100
            do {
                uiState.scrubThumbnails = try await library.videoScrubThumbnails(
                    for: item,
                    count: count,
                    size: .large
                )
            } catch {
                uiState.scrubThumbnails = []
            }
        }
    }

    private func exitScrubMode() {
        guard uiState.isScrubModeActive else { return }

        viewModel.scrubber.seek(toPercentage: Double(uiState.scrubPosition))
        uiState.isScrubModeActive = false

        if uiState.wasPlayingBeforeScrub && !viewModel.isPlaying {
            viewModel.togglePlayback()
        }
    }
}

// MARK: - Extracted Modifiers (split to aid Swift type-checker)

private struct SlideshowPersistenceModifier: ViewModifier {
    @Bindable var viewModel: SlideshowViewModel
    let uiState: SlideshowUIState
    let settings: AppSettings?
    let library: MediaLibrary
    let startVideoCaptionTimer: () -> Void
    let loadTranscriptCues: () -> Void
    let setFocused: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let settings {
                    viewModel.configure(settings: settings)
                }
                viewModel.configure(library: library)
                loadTranscriptCues()
                DispatchQueue.main.async { setFocused() }
            }
            .onChange(of: viewModel.slideDuration) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.videoPlayDuration) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.randomizeClipLocation) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.playFullGIF) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.loop) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.volume) { _, _ in
                viewModel.persistToSettings()
                viewModel.syncVolumeToAudioCaption()
            }
            .onChange(of: viewModel.isMuted) { _, _ in
                viewModel.persistToSettings()
                viewModel.syncVolumeToAudioCaption()
            }
            .onChange(of: viewModel.isRandomMode) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.showTimerBar) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.currentIndex) { _, _ in
                startVideoCaptionTimer()
                loadTranscriptCues()
            }
            .onChange(of: viewModel.showSubtitles) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.playAudioCaptions) { _, newValue in
                viewModel.persistToSettings()
                if newValue {
                    viewModel.playAudioCaptionIfNeeded()
                } else {
                    viewModel.stopAudioCaption()
                }
            }
            .onChange(of: viewModel.showCaptions) { _, newValue in
                viewModel.persistToSettings()
                if newValue {
                    startVideoCaptionTimer()
                } else {
                    uiState.videoCaptionTask?.cancel()
                    uiState.showVideoCaptions = false
                }
            }
    }
}

private struct SlideshowMenuSyncModifier: ViewModifier {
    let viewModel: SlideshowViewModel
    let settings: AppSettings?

    func body(content: Content) -> some View {
        content
            .onChange(of: settings?.showCaptions) { _, newValue in
                if let newValue, newValue != viewModel.showCaptions {
                    viewModel.showCaptions = newValue
                }
            }
            .onChange(of: settings?.showSubtitles) { _, newValue in
                if let newValue, newValue != viewModel.showSubtitles {
                    viewModel.showSubtitles = newValue
                }
            }
            .onChange(of: settings?.videoPlayDuration) { _, newValue in
                if let newValue, newValue != viewModel.videoPlayDuration {
                    viewModel.videoPlayDuration = newValue
                }
            }
            .onChange(of: settings?.loopSlideshow) { _, newValue in
                if let newValue, newValue != viewModel.loop {
                    viewModel.loop = newValue
                }
            }
            .onChange(of: settings?.shuffleSlideshow) { _, newValue in
                if let newValue, newValue != viewModel.isRandomMode {
                    viewModel.isRandomMode = newValue
                }
            }
            .onChange(of: settings?.showTimerBar) { _, newValue in
                if let newValue, newValue != viewModel.showTimerBar {
                    viewModel.showTimerBar = newValue
                }
            }
            .onChange(of: settings?.playFullGIF) { _, newValue in
                if let newValue, newValue != viewModel.playFullGIF {
                    viewModel.playFullGIF = newValue
                }
            }
            .onChange(of: settings?.defaultImageDuration) { _, newValue in
                if let newValue, newValue != viewModel.slideDuration {
                    viewModel.slideDuration = newValue
                }
            }
            .onChange(of: settings?.playAudioCaptions) { _, newValue in
                if let newValue, newValue != viewModel.playAudioCaptions {
                    viewModel.playAudioCaptions = newValue
                }
            }
    }
}

private struct SlideshowUIObserverModifier: ViewModifier {
    let uiState: SlideshowUIState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                uiState.isFullscreen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                uiState.isFullscreen = false
            }
            .onChange(of: uiState.showTimerPopover) { _, isOpen in
                if !isOpen { uiState.showControlsTemporarily() }
            }
            .onChange(of: uiState.showVideoPopover) { _, isOpen in
                if !isOpen { uiState.showControlsTemporarily() }
            }
    }
}
