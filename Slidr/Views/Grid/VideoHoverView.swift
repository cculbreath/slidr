import SwiftUI
import SwiftData
import AVKit

struct VideoHoverView: View {
    let item: MediaItem
    let size: ThumbnailSize
    @Binding var hoverState: HoverState

    @Environment(MediaLibrary.self) private var library
    @Environment(HoverVideoPlayer.self) private var hoverPlayer
    @Query private var settingsQuery: [AppSettings]
    @State private var scrubThumbnails: [NSImage] = []
    @State private var isLoading = true
    @State private var playbackTimer: Task<Void, Never>?

    private var scrubThumbnailCount: Int {
        settingsQuery.first?.scrubThumbnailCount ?? 100
    }

    var body: some View {
        ZStack {
            if hoverState.isPlaying, let player = hoverPlayer.avPlayer {
                VideoPlayer(player: player)
                    .disabled(true)
            } else if !scrubThumbnails.isEmpty {
                let index = scrubIndex(for: hoverState.position)
                Image(nsImage: scrubThumbnails[index])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                AsyncThumbnailImage(item: item, size: size)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }

            // Duration badge
            if !hoverState.isPlaying, let duration = item.formattedDuration {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(duration)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.7))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }
            }

            // Scrub position indicator (only during scrubbing)
            if hoverState.isScrubbing {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 2, height: 4)
                            .position(x: geo.size.width * hoverState.position, y: 2)
                    }
                    .frame(height: 4)
                }
            }
        }
        .task {
            await loadScrubThumbnails()
        }
        .onChange(of: hoverState) { oldState, newState in
            handleStateTransition(from: oldState, to: newState)
        }
        .onDisappear {
            cancelTimer()
            hoverPlayer.stop()
        }
    }

    private func scrubIndex(for position: Double) -> Int {
        guard !scrubThumbnails.isEmpty else { return 0 }
        let index = Int(position * Double(scrubThumbnails.count))
        return max(0, min(index, scrubThumbnails.count - 1))
    }

    private func handleStateTransition(from oldState: HoverState, to newState: HoverState) {
        switch newState {
        case .scrubbing:
            cancelTimer()
            if oldState.isPlaying {
                hoverPlayer.pause()
            }
            // Start delay timer for potential playback
            let position = newState.position
            playbackTimer = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                hoverState = .pendingPlayback(position: position)
            }

        case .pendingPlayback(let position):
            let fileURL = library.absoluteURL(for: item)
            hoverPlayer.prepare(url: fileURL, contentHash: item.contentHash)
            // Brief buffer then start playing
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard case .pendingPlayback = hoverState else { return }
                hoverState = .playing(position: position)
            }

        case .playing(let position):
            let duration = item.duration ?? 0
            if duration > 0 {
                hoverPlayer.play(from: position, duration: duration)
            }

        case .idle:
            cancelTimer()
            hoverPlayer.stop()
        }
    }

    private func cancelTimer() {
        playbackTimer?.cancel()
        playbackTimer = nil
    }

    private func loadScrubThumbnails() async {
        isLoading = true

        do {
            scrubThumbnails = try await library.videoScrubThumbnails(
                for: item,
                count: scrubThumbnailCount,
                size: size
            )
        } catch {
            scrubThumbnails = []
        }

        isLoading = false
    }
}
