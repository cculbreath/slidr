import AVFoundation
import OSLog

@MainActor
@Observable
final class HoverVideoPlayer {
    private(set) var avPlayer: AVPlayer?
    private(set) var currentContentHash: String?
    private var loopObserver: NSObjectProtocol?

    func prepare(url: URL, contentHash: String) {
        // Skip if already prepared for this item
        if currentContentHash == contentHash, avPlayer != nil {
            return
        }

        stop()

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false

        avPlayer = player
        currentContentHash = contentHash

        // Loop playback
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        Logger.hoverPlayer.debug("Prepared player for \(contentHash)")
    }

    func play(from position: Double, duration: Double) {
        guard let player = avPlayer else { return }

        let seekTime = CMTime(seconds: position * duration, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)

        player.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak player] finished in
            if finished {
                player?.play()
            }
        }

        Logger.hoverPlayer.debug("Playing from position \(position)")
    }

    func pause() {
        avPlayer?.pause()
    }

    func stop() {
        avPlayer?.pause()
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        avPlayer = nil
        currentContentHash = nil
    }
}
