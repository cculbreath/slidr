import SwiftUI
import SwiftData

struct SlideshowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaLibrary.self) private var library
    @Bindable var viewModel: SlideshowViewModel
    @Query private var settingsQuery: [AppSettings]

    @State private var showControls = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showCaptions: Bool = false
    @State private var showInfoOverlay: Bool = false
    @State private var ratingFeedback: Int? = nil

    private var settings: AppSettings? { settingsQuery.first }

    var body: some View {
        slideshowContent
            .focusable()
            .modifier(SlideshowKeyboardModifier(viewModel: viewModel, dismiss: dismiss))
            .modifier(CaptionKeys(showCaptions: $showCaptions))
            .modifier(RatingKeys(viewModel: viewModel, ratingFeedback: $ratingFeedback))
            .modifier(ExtraNavigationKeys(
                viewModel: viewModel,
                showInfoOverlay: $showInfoOverlay
            ))
    }

    @ViewBuilder
    private var slideshowContent: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Current media
            mediaContent

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
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
        .animation(.easeInOut(duration: 0.2), value: showInfoOverlay)
        .animation(.easeInOut(duration: 0.15), value: ratingFeedback)
        .onAppear {
            showControlsTemporarily()
        }
        .onHover { hovering in
            if hovering {
                showControlsTemporarily()
            }
        }
        .onTapGesture {
            showControlsTemporarily()
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if let item = viewModel.currentItem {
            Group {
                if item.isVideo {
                    VideoPlayerView(
                        item: item,
                        libraryRoot: library.libraryRoot,
                        isPlaying: $viewModel.isPlaying,
                        volume: $viewModel.volume,
                        isMuted: $viewModel.isMuted,
                        scrubber: viewModel.scrubber,
                        onVideoEnded: { viewModel.onVideoEnded() }
                    )
                } else {
                    AsyncThumbnailImage(item: item, size: .extraLarge)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .caption(
                for: item,
                show: showCaptions,
                template: settings?.captionTemplate ?? "{filename}",
                position: settings?.captionPosition ?? .bottom,
                fontSize: settings?.captionFontSize ?? 16
            )
            .id(item.id)
            .transition(.opacity)
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
            bottomControls
        }
        .foregroundStyle(.white)
        .transition(.opacity)
    }

    @ViewBuilder
    private var topBar: some View {
        HStack {
            Text("\(viewModel.currentIndex + 1) / \(viewModel.activeItems.count)")
                .font(.headline)

            if let item = viewModel.currentItem, item.isRated {
                Text(item.ratingStars)
                    .font(.subheadline)
            }

            Spacer()

            Button {
                showInfoOverlay.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help("Info (I)")

            Button {
                viewModel.toggleRandomMode()
            } label: {
                Image(systemName: viewModel.isRandomMode ? "shuffle.circle.fill" : "shuffle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help("Shuffle (R)")

            Button {
                toggleFullscreen()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help("Fullscreen (F)")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var videoScrubber: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(height: 4)
                    Rectangle()
                        .fill(.white)
                        .frame(width: geometry.size.width * viewModel.scrubber.progress, height: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let percentage = value.location.x / geometry.size.width
                            viewModel.scrubber.seek(toPercentage: Double(percentage))
                        }
                )
            }
            .frame(height: 4)

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
    private var bottomControls: some View {
        HStack(spacing: 24) {
            Button {
                viewModel.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .disabled(!viewModel.hasPrevious)

            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
            }

            Button {
                viewModel.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .disabled(!viewModel.hasNext)

            if viewModel.currentItemHasAudio {
                Divider()
                    .frame(height: 24)
                VolumeSlider(
                    volume: $viewModel.volume,
                    isMuted: $viewModel.isMuted
                )
            }
        }
        .buttonStyle(.plain)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func showControlsTemporarily() {
        hideControlsTask?.cancel()
        showControls = true
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                showControls = false
            }
        }
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
}

// MARK: - Keyboard Modifiers

/// Composed keyboard modifier to keep body expression manageable
private struct SlideshowKeyboardModifier: ViewModifier {
    let viewModel: SlideshowViewModel
    let dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            .modifier(BasicNavigationKeys(viewModel: viewModel, dismiss: dismiss))
            .modifier(VideoSeekKeys(viewModel: viewModel))
            .modifier(VolumeKeys(viewModel: viewModel))
    }
}

private struct BasicNavigationKeys: ViewModifier {
    let viewModel: SlideshowViewModel
    let dismiss: DismissAction

    func body(content: Content) -> some View {
        content
            .onKeyPress(.space) {
                viewModel.togglePlayback()
                return .handled
            }
            .onKeyPress(.escape) {
                dismiss()
                return .handled
            }
            .onKeyPress(keys: [.rightArrow, .leftArrow]) { press in
                if press.key == .rightArrow {
                    viewModel.next()
                } else {
                    viewModel.previous()
                }
                return .handled
            }
    }
}

private struct VideoSeekKeys: ViewModifier {
    let viewModel: SlideshowViewModel

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: .down) { press in
                handleVideoSeek(press)
            }
    }

    private func handleVideoSeek(_ press: KeyPress) -> KeyPress.Result {
        let hasShift = press.modifiers.contains(.shift)
        let hasOption = press.modifiers.contains(.option)

        // Shift + right arrow = seek forward 5s
        if press.key == .rightArrow && hasShift {
            viewModel.seekVideo(by: .fiveSeconds, forward: true)
            return .handled
        }
        // Shift + left arrow = seek back 5s
        if press.key == .leftArrow && hasShift {
            viewModel.seekVideo(by: .fiveSeconds, forward: false)
            return .handled
        }
        // Option + right arrow = seek forward 10s
        if press.key == .rightArrow && hasOption {
            viewModel.seekVideo(by: .tenSeconds, forward: true)
            return .handled
        }
        // Option + left arrow = seek back 10s
        if press.key == .leftArrow && hasOption {
            viewModel.seekVideo(by: .tenSeconds, forward: false)
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
        // Down arrow = volume down
        if press.key == .downArrow {
            viewModel.decreaseVolume()
            return .handled
        }
        return .ignored
    }
}

private struct CaptionKeys: ViewModifier {
    @Binding var showCaptions: Bool

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            if press.key == KeyEquivalent("c") {
                showCaptions.toggle()
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
