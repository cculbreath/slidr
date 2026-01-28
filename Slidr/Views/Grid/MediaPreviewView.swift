import SwiftUI

struct MediaPreviewView: View {
    let item: MediaItem
    let items: [MediaItem]
    let library: MediaLibrary
    let onDismiss: () -> Void

    @State private var currentItem: MediaItem
    @State private var scrubber = SmoothScrubber()
    @State private var isPlaying = true
    @State private var volume: Float = 1.0
    @State private var isMuted = false
    @FocusState private var isFocused: Bool

    init(item: MediaItem, items: [MediaItem], library: MediaLibrary, onDismiss: @escaping () -> Void) {
        self.item = item
        self.items = items
        self.library = library
        self.onDismiss = onDismiss
        self._currentItem = State(initialValue: item)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            mediaContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom metadata overlay
            VStack {
                Spacer()
                HStack {
                    Text(currentItem.originalFilename)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    if let dims = currentItem.dimensions {
                        Text("\(Int(dims.width)) x \(Int(dims.height))")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial.opacity(0.5))
            }
        }
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.space) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            navigatePrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateNext()
            return .handled
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if currentItem.isVideo {
            VideoPlayerView	(
                item: currentItem,
                fileURL: library.absoluteURL(for: currentItem),
                isPlaying: $isPlaying,
                volume: $volume,
                isMuted: $isMuted,
                scrubber: scrubber,
                onVideoEnded: {}
            )
        } else if currentItem.isAnimated {
            AsyncAnimatedGIFView(item: currentItem)
        } else {
            AsyncThumbnailImage(item: currentItem, size: .large, contentMode: .fit)
        }
    }

    private func navigateNext() {
        guard let currentIndex = items.firstIndex(where: { $0.id == currentItem.id }),
              currentIndex < items.count - 1 else { return }
        currentItem = items[currentIndex + 1]
    }

    private func navigatePrevious() {
        guard let currentIndex = items.firstIndex(where: { $0.id == currentItem.id }),
              currentIndex > 0 else { return }
        currentItem = items[currentIndex - 1]
    }
}
