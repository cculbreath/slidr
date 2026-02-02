import AppKit
import SwiftUI

@MainActor
final class SlideshowControlsWindowController: NSWindowController {
    private let viewModel: SlideshowViewModel
    private let uiState: SlideshowUIState
    private let goNext: () -> Void
    private let goPrevious: () -> Void
    private let onDismiss: () -> Void

    init(
        viewModel: SlideshowViewModel,
        uiState: SlideshowUIState,
        goNext: @escaping () -> Void,
        goPrevious: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.uiState = uiState
        self.goNext = goNext
        self.goPrevious = goPrevious
        self.onDismiss = onDismiss

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 100),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = "Slideshow Controls"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("SlideshowControlsPosition")
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let content = FloatingControlsContent(
            viewModel: viewModel,
            uiState: uiState,
            goNext: goNext,
            goPrevious: goPrevious,
            onDismiss: onDismiss
        )
        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        showWindow(nil)
        window?.center()
    }
}

// MARK: - Floating Controls Content

private struct FloatingControlsContent: View {
    @Bindable var viewModel: SlideshowViewModel
    let uiState: SlideshowUIState
    let goNext: () -> Void
    let goPrevious: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Position indicator
            HStack {
                Text("\(viewModel.currentIndex + 1) / \(viewModel.activeItems.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                if let item = viewModel.currentItem, item.isRated {
                    Text(item.ratingStars)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Video scrubber (when current item is video)
            if viewModel.currentItemIsVideo {
                videoScrubber
            }

            // Shared control bar
            SlideshowControlBar(
                viewModel: viewModel,
                uiState: uiState,
                goNext: goNext,
                goPrevious: goPrevious,
                onDismiss: onDismiss
            )
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .background(.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    // MARK: - Video Scrubber

    @ViewBuilder
    private var videoScrubber: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(height: 4)

                    if viewModel.scrubber.hasClipRegion {
                        Rectangle()
                            .fill(.white.opacity(0.35))
                            .frame(
                                width: width * viewModel.scrubber.clipLengthFraction,
                                height: 4
                            )
                            .offset(x: width * viewModel.scrubber.clipStartFraction)
                    }

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
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}
