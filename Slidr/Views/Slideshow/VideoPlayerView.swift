import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let item: MediaItem
    let libraryRoot: URL
    @Binding var isPlaying: Bool
    @Binding var volume: Float
    @Binding var isMuted: Bool
    let scrubber: SmoothScrubber
    let onVideoEnded: () -> Void

    @State private var player: AVPlayer?
    @State private var playerObserver: Any?

    var body: some View {
        GeometryReader { geometry in
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true) // We handle controls ourselves
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
        let fileURL = libraryRoot.appendingPathComponent(item.relativePath)
        let playerItem = AVPlayerItem(url: fileURL)
        let newPlayer = AVPlayer(playerItem: playerItem)

        newPlayer.volume = isMuted ? 0 : volume

        // Observe when video ends
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            onVideoEnded()
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

        scrubber.detach()
        player?.pause()
        player = nil
    }
}
