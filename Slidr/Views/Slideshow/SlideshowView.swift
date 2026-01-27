import SwiftUI

struct SlideshowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaLibrary.self) private var library
    @Bindable var viewModel: SlideshowViewModel

    @State private var showControls = false
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        slideshowContent
            .focusable()
            .modifier(SlideshowKeyboardModifier(viewModel: viewModel, dismiss: dismiss))
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
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentIndex)
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
            Text("\(viewModel.currentIndex + 1) / \(viewModel.items.count)")
                .font(.headline)
            Spacer()
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
            viewModel.volume = min(1.0, viewModel.volume + 0.1)
            return .handled
        }
        // Down arrow = volume down
        if press.key == .downArrow {
            viewModel.volume = max(0.0, viewModel.volume - 0.1)
            return .handled
        }
        return .ignored
    }
}
