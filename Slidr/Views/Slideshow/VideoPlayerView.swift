import SwiftUI
import AVKit
import OSLog

struct VideoPlayerView: View {
    let item: MediaItem
    let fileURL: URL
    @Binding var isPlaying: Bool
    @Binding var volume: Float
    @Binding var isMuted: Bool
    let scrubber: SmoothScrubber
    let onVideoEnded: () -> Void

    @State private var player: AVPlayer?
    @State private var playerObserver: Any?
    @State private var errorObserver: Any?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var hasError = false

    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "VideoPlayer")

    var body: some View {
        GeometryReader { geometry in
            if hasError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text("Unable to play video")
                        .font(.headline)
                    Text("This video format may not be supported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let player = player {
                NoControlsPlayerView(player: player)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: item.id) {
            hasError = false
            teardownPlayer()
            setupPlayer()
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue {
                player?.play()
            } else {
                player?.pause()
            }
        }
        .onChange(of: volume) { _, newValue in
            player?.volume = isMuted ? 0 : newValue
        }
        .onChange(of: isMuted) { _, newValue in
            player?.volume = newValue ? 0 : volume
        }
    }

    private func setupPlayer() {
        let playerItem = AVPlayerItem(url: fileURL)
        let newPlayer = AVPlayer(playerItem: playerItem)

        newPlayer.volume = isMuted ? 0 : volume
        newPlayer.automaticallyWaitsToMinimizeStalling = false

        // Observe when video ends
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            onVideoEnded()
        }

        // Observe playback errors
        errorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                Self.logger.error("Video playback failed: \(error.localizedDescription)")
            }
            hasError = true
            // Auto-advance after showing error briefly
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if hasError {
                    onVideoEnded()
                }
            }
        }

        // Observe player item status for load errors
        statusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
            Task { @MainActor in
                if item.status == .failed {
                    if let error = item.error {
                        Self.logger.error("Video failed to load: \(error.localizedDescription)")
                    }
                    hasError = true
                    // Auto-advance after showing error briefly
                    try? await Task.sleep(for: .seconds(2))
                    if hasError {
                        onVideoEnded()
                    }
                }
            }
        }

        // Attach scrubber
        scrubber.attach(to: newPlayer)

        self.player = newPlayer

        if isPlaying {
            newPlayer.play()
        }
    }

    private func teardownPlayer() {
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
            playerObserver = nil
        }

        if let observer = errorObserver {
            NotificationCenter.default.removeObserver(observer)
            errorObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        if let player = player {
            scrubber.detach(from: player)
            player.pause()
        }
        player = nil
    }
}

// MARK: - AVPlayerView without native controls or key handling

private class KeyPassthroughPlayerView: AVPlayerView {
    override func keyDown(with event: NSEvent) {
        nextResponder?.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        nextResponder?.keyUp(with: event)
    }
}

private struct NoControlsPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> KeyPassthroughPlayerView {
        let view = KeyPassthroughPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: KeyPassthroughPlayerView, context: Context) {
        nsView.player = player
    }
}
