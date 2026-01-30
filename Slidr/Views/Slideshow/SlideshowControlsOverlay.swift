import SwiftUI
import SwiftData

/// Controls overlay for the slideshow, including top bar, video scrubber, and bottom control buttons.
struct SlideshowControlsOverlay: View {
    @Bindable var viewModel: SlideshowViewModel
    let uiState: SlideshowUIState
    let goNext: () -> Void
    let goPrevious: () -> Void
    let onDismiss: () -> Void

    var body: some View {
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

    // MARK: - Top Bar

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

    // MARK: - Video Scrubber

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

    // MARK: - Draggable Bottom Controls

    @ViewBuilder
    private var draggableBottomControls: some View {
        bottomControls
            .gesture(
                DragGesture()
                    .onChanged { value in
                        uiState.isDraggingControls = true
                        uiState.hideControlsTask?.cancel()
                        uiState.controlsDragOffset = value.translation
                    }
                    .onEnded { value in
                        uiState.isDraggingControls = false
                        uiState.controlsOffset = CGSize(
                            width: uiState.controlsOffset.width + value.translation.width,
                            height: uiState.controlsOffset.height + value.translation.height
                        )
                        uiState.controlsDragOffset = .zero
                        uiState.scheduleHideControls()
                    }
            )
            .offset(
                x: uiState.controlsOffset.width + uiState.controlsDragOffset.width,
                y: uiState.controlsOffset.height + uiState.controlsDragOffset.height
            )
    }

    // MARK: - Bottom Controls

    @ViewBuilder
    private var bottomControls: some View {
        HStack(spacing: 20) {
            // Group 1: Prev / Play-Pause / Next
            navigationGroup

            Divider().frame(height: 28)

            // Group 2: Shuffle & Repeat
            shuffleRepeatGroup

            Divider().frame(height: 28)

            // Group 3: Timer Duration, Full GIF Toggle, Video Menu
            timerVideoGroup

            Divider().frame(height: 28)

            // Group 4: Show Timer Bar, Show Info, Show Captions
            togglesGroup

            Divider().frame(height: 28)

            // Group 5: Fullscreen
            fullscreenButton

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

    // MARK: - Control Groups

    private var navigationGroup: some View {
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
    }

    private var shuffleRepeatGroup: some View {
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
    }

    @ViewBuilder
    private var timerVideoGroup: some View {
        HStack(spacing: 20) {
            // Timer duration popover
            Button {
                uiState.showTimerPopover.toggle()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.title)
            }
            .popover(isPresented: Binding(
                get: { uiState.showTimerPopover },
                set: { uiState.showTimerPopover = $0 }
            )) {
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
                uiState.showVideoPopover.toggle()
            } label: {
                Image("custom.video.timer")
                    .font(.title)
                    .toggleGlow(!viewModel.videoPlayDuration.isFullVideo)
            }
            .popover(isPresented: Binding(
                get: { uiState.showVideoPopover },
                set: { uiState.showVideoPopover = $0 }
            )) {
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
    }

    private var togglesGroup: some View {
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
                uiState.showInfoOverlay.toggle()
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
    }

    private var fullscreenButton: some View {
        Button {
            if let window = NSApplication.shared.keyWindow {
                window.toggleFullScreen(nil)
            }
        } label: {
            Image(systemName: uiState.isFullscreen
                ? "arrow.down.right.and.arrow.up.left.rectangle"
                : "arrow.up.left.and.arrow.down.right.rectangle")
                .font(.title)
        }
        .help("Fullscreen (F)")
    }
}
