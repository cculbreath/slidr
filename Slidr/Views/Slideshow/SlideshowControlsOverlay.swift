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
        SlideshowControlBar(
            viewModel: viewModel,
            uiState: uiState,
            goNext: goNext,
            goPrevious: goPrevious,
            onDismiss: onDismiss
        )
        .padding()
    }
}
