import SwiftUI

/// Overlay for Option-key scrub mode with thumbnail preview and position indicator.
struct SlideshowScrubModeView: View {
    let viewModel: SlideshowViewModel
    let uiState: SlideshowUIState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Show scrub thumbnail
                let index = scrubIndex(for: uiState.scrubPosition)
                Image(nsImage: uiState.scrubThumbnails[index])
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
                            .frame(width: geo.size.width * uiState.scrubPosition, height: 6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 60)
                }

                // Time indicator
                VStack {
                    Spacer()
                    if let duration = viewModel.currentItem?.duration {
                        Text(formatTime(Double(uiState.scrubPosition) * duration))
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
                        Label("Scrubbing (\u{2325})", systemImage: "slider.horizontal.below.rectangle")
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
                    uiState.scrubPosition = max(0, min(1, location.x / geo.size.width))
                }
            }
        }
        .transition(.opacity)
    }

    // MARK: - Helpers

    private func scrubIndex(for position: CGFloat) -> Int {
        guard !uiState.scrubThumbnails.isEmpty else { return 0 }
        let index = Int(position * CGFloat(uiState.scrubThumbnails.count))
        return max(0, min(index, uiState.scrubThumbnails.count - 1))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
