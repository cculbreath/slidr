import SwiftUI

struct SlideshowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaLibrary.self) private var library
    @Bindable var viewModel: SlideshowViewModel

    @State private var showControls = false
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Current media
            if let item = viewModel.currentItem {
                AsyncThumbnailImage(item: item, size: .extraLarge)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(item.id)
                    .transition(.opacity)
            }

            // Controls overlay
            if showControls {
                VStack {
                    // Top bar
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

                    Spacer()

                    // Bottom controls
                    HStack(spacing: 32) {
                        Button {
                            viewModel.previous()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.title)
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
                                .font(.title)
                        }
                        .disabled(!viewModel.hasNext)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
                .foregroundStyle(.white)
                .transition(.opacity)
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
        .focusable()
        .onKeyPress(.space) {
            viewModel.togglePlayback()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.next()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            viewModel.previous()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
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
