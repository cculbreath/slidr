import SwiftUI
import SwiftData

struct SlideshowView: View {
    @Environment(MediaLibrary.self) private var library
    @Bindable var viewModel: SlideshowViewModel
    var onDismiss: () -> Void
    @Query private var settingsQuery: [AppSettings]

    @FocusState private var isFocused: Bool
    @State private var showControls = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showVideoCaptions: Bool = false
    @State private var videoCaptionTask: Task<Void, Never>?
    @State private var showInfoOverlay: Bool = false
    @State private var ratingFeedback: Int? = nil
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var isFullscreen: Bool = false
    @State private var showTimerPopover: Bool = false
    @State private var showVideoPopover: Bool = false
    @State private var lastMouseLocation: CGPoint = .zero
    @State private var controlsOffset: CGSize = .zero
    @State private var controlsDragOffset: CGSize = .zero
    @State private var isDraggingControls: Bool = false

    // Scrub mode state (Option-key scrubbing)
    @State private var isScrubModeActive: Bool = false
    @State private var scrubThumbnails: [NSImage] = []
    @State private var scrubPosition: CGFloat = 0
    @State private var wasPlayingBeforeScrub: Bool = false
    @State private var optionKeyMonitor: Any?

    private var settings: AppSettings? { settingsQuery.first }

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
            return showVideoCaptions
        }
        return true
    }

    var body: some View {
        slideshowContent
            .focusable()
            .focused($isFocused)
            .modifier(SlideshowKeyboardModifier(viewModel: viewModel, onDismiss: onDismiss, goNext: goNext, goPrevious: goPrevious))
            .modifier(CaptionKeys(viewModel: viewModel))
            .modifier(RatingKeys(viewModel: viewModel, ratingFeedback: $ratingFeedback))
            .modifier(ExtraNavigationKeys(
                viewModel: viewModel,
                showInfoOverlay: $showInfoOverlay,
                showTimerBar: $viewModel.showTimerBar
            ))
            .onAppear {
                if let settings {
                    viewModel.configure(settings: settings)
                }
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            .onChange(of: viewModel.slideDuration) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.videoPlayDuration) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.randomizeClipLocation) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.playFullGIF) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.loop) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.volume) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.isMuted) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.isRandomMode) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.showTimerBar) { _, _ in viewModel.persistToSettings() }
            .onChange(of: viewModel.currentIndex) { _, _ in
                startVideoCaptionTimer()
            }
            .onChange(of: viewModel.showCaptions) { _, newValue in
                viewModel.persistToSettings()
                if newValue {
                    startVideoCaptionTimer()
                } else {
                    videoCaptionTask?.cancel()
                    showVideoCaptions = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                isFullscreen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                isFullscreen = false
            }
            .onChange(of: showTimerPopover) { _, isOpen in
                if !isOpen { showControlsTemporarily() }
            }
            .onChange(of: showVideoPopover) { _, isOpen in
                if !isOpen { showControlsTemporarily() }
            }
    }

    @ViewBuilder
    private var slideshowContent: some View {
        ZStack {
            // Background — tap here to show controls and reclaim focus
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    showControlsTemporarily()
                    isFocused = true
                }

            // Current media — tap here to show controls and reclaim focus
            mediaContent
                .animation(.easeInOut(duration: transitionDuration), value: viewModel.currentIndex)
                .onTapGesture {
                    showControlsTemporarily()
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

            // Controls overlay
            if showControls {
                controlsOverlay
            }

            // Info overlay
            if showInfoOverlay, let item = viewModel.currentItem {
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
            if let rating = ratingFeedback {
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
                    .padding(.top, showControls ? 60 : 16)
                    Spacer()
                }
            }

            // Scrub mode overlay (Option-key scrubbing)
            if isScrubModeActive, viewModel.currentItemIsVideo, !scrubThumbnails.isEmpty {
                scrubModeOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .animation(.easeInOut(duration: 0.2), value: showInfoOverlay)
        .animation(.easeInOut(duration: 0.15), value: ratingFeedback)
        .animation(.easeInOut(duration: 0.15), value: isScrubModeActive)
        .onAppear {
            showControlsTemporarily()
            setupOptionKeyMonitor()
        }
        .onDisappear {
            removeOptionKeyMonitor()
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                // Only trigger if mouse actually moved
                if location != lastMouseLocation {
                    lastMouseLocation = location
                    showControlsTemporarily()
                }
            case .ended:
                break
            }
        }
    }

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

    @ViewBuilder
    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if viewModel.currentItemIsVideo {
                videoScrubber
            }
            draggableBottomControls
        }
        .foregroundStyle(.white)
        .transition(.opacity)
        .animation(nil, value: viewModel.currentIndex)
    }

    @ViewBuilder
    private var draggableBottomControls: some View {
        bottomControls
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDraggingControls = true
                        hideControlsTask?.cancel()
                        controlsDragOffset = value.translation
                    }
                    .onEnded { value in
                        isDraggingControls = false
                        controlsOffset = CGSize(
                            width: controlsOffset.width + value.translation.width,
                            height: controlsOffset.height + value.translation.height
                        )
                        controlsDragOffset = .zero
                        scheduleHideControls()
                    }
            )
            .offset(
                x: controlsOffset.width + controlsDragOffset.width,
                y: controlsOffset.height + controlsDragOffset.height
            )
    }

    @ViewBuilder
    private var videoScrubber: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    // Full timeline background
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(height: 4)

                    // Clip region highlight (when duration is limited)
                    if viewModel.scrubber.hasClipRegion {
                        Rectangle()
                            .fill(.white.opacity(0.35))
                            .frame(
                                width: width * viewModel.scrubber.clipLengthFraction,
                                height: 4
                            )
                            .offset(x: width * viewModel.scrubber.clipStartFraction)
                    }

                    // Playback progress
                    Rectangle()
                        .fill(.white)
                        .frame(
                            width: width * viewModel.scrubber.progress,
                            height: 4
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percentage = value.location.x / width
                            viewModel.scrubber.seek(toPercentage: Double(percentage))
                        }
                )
            }
            .frame(height: 24)

            HStack {
                Text(viewModel.scrubber.currentTimeFormatted)
                    .font(.caption)
                    .monospacedDigit()
                Spacer()
                Text(viewModel.scrubber.durationFormatted)
                    .font(.caption)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Text("\(viewModel.currentIndex + 1) / \(viewModel.activeItems.count)")
                .font(.title3)

            if let item = viewModel.currentItem, item.isRated {
                Text(item.ratingStars)
                    .font(.title3)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .opacity(0.7)
        .padding()
    }

    @ViewBuilder
    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Group 1: Prev / Play-Pause / Next
            HStack(spacing: 24) {
                Button {
                    goPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 28, weight: .medium))
                }
                .disabled(!viewModel.hasPrevious)

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                }

                Button {
                    goNext()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 28, weight: .medium))
                }
                .disabled(!viewModel.hasNext)
            }

            Divider().frame(height: 28)

            // Group 2: Shuffle & Repeat
            HStack(spacing: 20) {
                Button {
                    viewModel.toggleRandomMode()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.title)
                        .toggleGlow(viewModel.isRandomMode)
                }
                .help("Shuffle (R)")

                Button {
                    viewModel.loop.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .font(.title)
                        .toggleGlow(viewModel.loop)
                }
                .help("Repeat")
            }

            Divider().frame(height: 28)

            // Group 3: Timer Duration, Full GIF Toggle, Video Menu
            HStack(spacing: 20) {
                // Timer duration popover
                Button {
                    showTimerPopover.toggle()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "timer")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(.title)
                }
                .popover(isPresented: $showTimerPopover) {
                    VStack(spacing: 12) {
                        Text("Slide Duration")
                            .font(.headline)
                        HStack {
                            Slider(value: $viewModel.slideDuration, in: 0...10, step: 0.5)
                                .frame(width: 200)
                            Text(String(format: "%.1fs", viewModel.slideDuration))
                                .monospacedDigit()
                                .frame(width: 44)
                        }
                    }
                    .padding()
                    .foregroundStyle(.primary)
                    .preferredColorScheme(.dark)
                }
                .help("Timer Duration")

                // Play full GIF toggle
                Button {
                    viewModel.playFullGIF.toggle()
                } label: {
                    Image("custom.gifs.timer")
                        .font(.title)
                        .toggleGlow(viewModel.playFullGIF)
                }
                .help(viewModel.playFullGIF ? "Play Full GIF: On" : "Play Full GIF: Off")

                // Video play duration popover
                Button {
                    showVideoPopover.toggle()
                } label: {
                    Image("custom.video.timer")
                        .font(.title)
                        .toggleGlow(!viewModel.videoPlayDuration.isFullVideo)
                }
                .popover(isPresented: $showVideoPopover) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Limit video duration to")
                            .font(.headline)

                        ForEach(VideoPlayDuration.presets.filter { !$0.isFullVideo }, id: \.self) { preset in
                            Button {
                                viewModel.videoPlayDuration = preset
                            } label: {
                                HStack {
                                    Image(systemName: viewModel.videoPlayDuration == preset ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(viewModel.videoPlayDuration == preset ? .blue : .secondary)
                                    Text(preset.label)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 12)
                        }

                        Toggle("Randomize start location", isOn: $viewModel.randomizeClipLocation)
                            .disabled(viewModel.videoPlayDuration.isFullVideo)
                            .padding(.leading, 12)

                        Divider()

                        Button {
                            viewModel.videoPlayDuration = .fullVideo
                        } label: {
                            HStack {
                                Image(systemName: viewModel.videoPlayDuration.isFullVideo ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(viewModel.videoPlayDuration.isFullVideo ? .blue : .secondary)
                                Text("Do not limit video duration")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .frame(width: 280)
                    .foregroundStyle(.primary)
                    .preferredColorScheme(.dark)
                }
                .help("Video Playback Duration")
            }

            Divider().frame(height: 28)

            // Group 4: Show Timer Bar, Show Info, Show Captions
            HStack(spacing: 20) {
                Button {
                    viewModel.showTimerBar.toggle()
                } label: {
                    Image(systemName: "hourglass.badge.eye")
                        .font(.title)
                        .toggleGlow(viewModel.showTimerBar)
                }
                .help("Toggle Timer Bar (T)")

                Button {
                    showInfoOverlay.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title)
                }
                .help("Info (I)")

                Button {
                    viewModel.showCaptions.toggle()
                } label: {
                    Image(systemName: viewModel.showCaptions ? "text.bubble.fill" : "text.bubble")
                        .font(.title)
                        .toggleGlow(viewModel.showCaptions)
                }
                .help("Toggle Captions (C)")
            }

            Divider().frame(height: 28)

            // Group 5: Fullscreen
            Button {
                toggleFullscreen()
            } label: {
                Image(systemName: isFullscreen
                    ? "arrow.down.right.and.arrow.up.left.rectangle"
                    : "arrow.up.left.and.arrow.down.right.rectangle")
                    .font(.title)
            }
            .help("Fullscreen (F)")

            // Volume (only when current item has audio)
            if viewModel.currentItemHasAudio {
                Divider().frame(height: 28)
                VolumeSlider(
                    volume: $viewModel.volume,
                    isMuted: $viewModel.isMuted
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private var isAnyPopoverOpen: Bool {
        showTimerPopover || showVideoPopover
    }

    private func showControlsTemporarily() {
        showControls = true
        scheduleHideControls()
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        guard !isAnyPopoverOpen && !isDraggingControls else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled && !isAnyPopoverOpen && !isDraggingControls {
                showControls = false
            }
        }
    }

    private func goNext() {
        navigationDirection = .forward
        viewModel.next()
    }

    private func goPrevious() {
        navigationDirection = .backward
        viewModel.previous()
    }

    private func startVideoCaptionTimer() {
        videoCaptionTask?.cancel()

        guard viewModel.showCaptions else {
            showVideoCaptions = false
            return
        }

        if viewModel.currentItemIsVideo {
            showVideoCaptions = true
            let duration = settings?.videoCaptionDuration ?? 5.0
            videoCaptionTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled {
                    withAnimation {
                        showVideoCaptions = false
                    }
                }
            }
        } else {
            showVideoCaptions = true
        }
    }

    private func timerProgress(at date: Date) -> Double {
        // If paused, show frozen progress
        if !viewModel.isPlaying {
            return viewModel.pausedTimerProgress
        }
        guard let start = viewModel.timerStartDate, viewModel.currentSlideDuration > 0 else {
            return 0
        }
        let elapsed = date.timeIntervalSince(start)
        return max(0, min(1.0, elapsed / viewModel.currentSlideDuration))
    }

    private func toggleFullscreen() {
        if let window = NSApplication.shared.keyWindow {
            window.toggleFullScreen(nil)
        }
    }

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

    // MARK: - Scrub Mode (Option-key scrubbing)

    @ViewBuilder
    private var scrubModeOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // Show scrub thumbnail
                let index = scrubIndex(for: scrubPosition)
                Image(nsImage: scrubThumbnails[index])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Scrub position indicator
                VStack {
                    Spacer()
                    ZStack(alignment: .leading) {
                        // Background bar
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(height: 6)

                        // Progress
                        Rectangle()
                            .fill(.white)
                            .frame(width: geo.size.width * scrubPosition, height: 6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
                }

                // Time indicator
                VStack {
                    Spacer()
                    if let duration = viewModel.currentItem?.duration {
                        Text(formatTime(scrubPosition * duration))
                            .font(.title2)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2)
                            .padding(.bottom, 80)
                    }
                }

                // "Scrubbing" label
                VStack {
                    HStack {
                        Label("Scrubbing (⌥)", systemImage: "slider.horizontal.below.rectangle")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    Spacer()
                }
            }
            .background(Color.black)
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    scrubPosition = max(0, min(1, location.x / geo.size.width))
                }
            }
        }
        .transition(.opacity)
    }

    private func scrubIndex(for position: CGFloat) -> Int {
        guard !scrubThumbnails.isEmpty else { return 0 }
        let index = Int(position * CGFloat(scrubThumbnails.count))
        return max(0, min(index, scrubThumbnails.count - 1))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func setupOptionKeyMonitor() {
        // Monitor for flags changed events (modifier keys)
        optionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let optionPressed = event.modifierFlags.contains(.option)

            if optionPressed && !isScrubModeActive && viewModel.currentItemIsVideo {
                enterScrubMode()
            } else if !optionPressed && isScrubModeActive {
                exitScrubMode()
            }

            return event
        }
    }

    private func removeOptionKeyMonitor() {
        if let monitor = optionKeyMonitor {
            NSEvent.removeMonitor(monitor)
            optionKeyMonitor = nil
        }
    }

    private func enterScrubMode() {
        guard let item = viewModel.currentItem, item.isVideo else { return }

        wasPlayingBeforeScrub = viewModel.isPlaying
        if viewModel.isPlaying {
            viewModel.togglePlayback()
        }

        // Set initial scrub position from current video position
        scrubPosition = viewModel.scrubber.progress

        isScrubModeActive = true

        // Load scrub thumbnails
        Task {
            let count = settings?.scrubThumbnailCount ?? 100
            do {
                scrubThumbnails = try await library.videoScrubThumbnails(
                    for: item,
                    count: count,
                    size: .large
                )
            } catch {
                scrubThumbnails = []
            }
        }
    }

    private func exitScrubMode() {
        guard isScrubModeActive else { return }

        // Seek to scrubbed position
        viewModel.scrubber.seek(toPercentage: Double(scrubPosition))

        isScrubModeActive = false

        // Resume playback if it was playing before
        if wasPlayingBeforeScrub && !viewModel.isPlaying {
            viewModel.togglePlayback()
        }
    }
}

// MARK: - Toggle Glow

private let glowColor = Color.cyan

private extension View {
    func toggleGlow(_ isOn: Bool) -> some View {
        self
            .foregroundStyle(isOn ? glowColor : .white.opacity(0.4))
            .shadow(color: isOn ? glowColor.opacity(0.7) : .clear, radius: 6)
            .shadow(color: isOn ? glowColor.opacity(0.4) : .clear, radius: 12)
            .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

// MARK: - Keyboard Modifiers

/// Composed keyboard modifier to keep body expression manageable
private struct SlideshowKeyboardModifier: ViewModifier {
    let viewModel: SlideshowViewModel
    let onDismiss: () -> Void
    let goNext: () -> Void
    let goPrevious: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(BasicNavigationKeys(onDismiss: onDismiss, goNext: goNext, goPrevious: goPrevious, togglePlayback: { viewModel.togglePlayback() }))
            .modifier(ArrowKeys(viewModel: viewModel, goNext: goNext, goPrevious: goPrevious))
            .modifier(VolumeKeys(viewModel: viewModel))
    }
}

private struct BasicNavigationKeys: ViewModifier {
    let onDismiss: () -> Void
    let goNext: () -> Void
    let goPrevious: () -> Void
    let togglePlayback: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.space) {
                togglePlayback()
                return .handled
            }
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
    }
}

private struct ArrowKeys: ViewModifier {
    let viewModel: SlideshowViewModel
    let goNext: () -> Void
    let goPrevious: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: .down) { press in
                handleArrowKey(press)
            }
    }

    private func handleArrowKey(_ press: KeyPress) -> KeyPress.Result {
        let hasShift = press.modifiers.contains(.shift)
        let hasOption = press.modifiers.contains(.option)

        // Shift + arrow = seek 5s
        if press.key == .rightArrow && hasShift {
            viewModel.seekVideo(by: .fiveSeconds, forward: true)
            return .handled
        }
        if press.key == .leftArrow && hasShift {
            viewModel.seekVideo(by: .fiveSeconds, forward: false)
            return .handled
        }
        // Option + arrow = seek 30s
        if press.key == .rightArrow && hasOption {
            viewModel.seekVideo(by: .thirtySeconds, forward: true)
            return .handled
        }
        if press.key == .leftArrow && hasOption {
            viewModel.seekVideo(by: .thirtySeconds, forward: false)
            return .handled
        }
        // Plain arrow = next/previous
        if press.key == .rightArrow {
            goNext()
            return .handled
        }
        if press.key == .leftArrow {
            goPrevious()
            return .handled
        }
        // Comma = step frame backward
        if press.key == KeyEquivalent(",") {
            viewModel.stepVideoFrame(forward: false)
            return .handled
        }
        // Period = step frame forward
        if press.key == KeyEquivalent(".") {
            viewModel.stepVideoFrame(forward: true)
            return .handled
        }
        return .ignored
    }
}

private struct VolumeKeys: ViewModifier {
    let viewModel: SlideshowViewModel

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: .down) { press in
                handleVolumeKey(press)
            }
    }

    private func handleVolumeKey(_ press: KeyPress) -> KeyPress.Result {
        // M = mute toggle
        if press.key == KeyEquivalent("m") {
            viewModel.toggleMute()
            return .handled
        }
        // Up arrow = volume up
        if press.key == .upArrow {
            viewModel.increaseVolume()
            return .handled
        }
        // K = volume up
        if press.key == KeyEquivalent("k") {
            viewModel.increaseVolume()
            return .handled
        }
        // Down arrow = volume down
        if press.key == .downArrow {
            viewModel.decreaseVolume()
            return .handled
        }
        return .ignored
    }
}

private struct CaptionKeys: ViewModifier {
    @Bindable var viewModel: SlideshowViewModel

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            if press.key == KeyEquivalent("c") {
                viewModel.showCaptions.toggle()
                return .handled
            }
            return .ignored
        }
    }
}

private struct RatingKeys: ViewModifier {
    let viewModel: SlideshowViewModel
    @Binding var ratingFeedback: Int?

    func body(content: Content) -> some View {
        content
            .onKeyPress("0") { rateItem(0); return .handled }
            .onKeyPress("1") { rateItem(1); return .handled }
            .onKeyPress("2") { rateItem(2); return .handled }
            .onKeyPress("3") { rateItem(3); return .handled }
            .onKeyPress("4") { rateItem(4); return .handled }
            .onKeyPress("5") { rateItem(5); return .handled }
    }

    private func rateItem(_ rating: Int) {
        viewModel.rateCurrentItem(rating)
        ratingFeedback = rating
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            ratingFeedback = nil
        }
    }
}

private struct ExtraNavigationKeys: ViewModifier {
    let viewModel: SlideshowViewModel
    @Binding var showInfoOverlay: Bool
    @Binding var showTimerBar: Bool

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            handleKey(press)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case KeyEquivalent("i"):
            showInfoOverlay.toggle()
            return .handled
        case KeyEquivalent("r"):
            viewModel.toggleRandomMode()
            return .handled
        case KeyEquivalent("f"):
            if let window = NSApplication.shared.keyWindow {
                window.toggleFullScreen(nil)
            }
            return .handled
        case KeyEquivalent("t"):
            showTimerBar.toggle()
            return .handled
        case KeyEquivalent("l"):
            viewModel.next()
            return .handled
        case KeyEquivalent("j"):
            viewModel.previous()
            return .handled
        default:
            return .ignored
        }
    }
}
