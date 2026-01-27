import Foundation
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.physicscloud.slidr", category: "Scrubber")

@MainActor
@Observable
final class SmoothScrubber {
    // MARK: - Published State
    private(set) var isSeeking = false
    private(set) var currentTime: CMTime = .zero
    private(set) var duration: CMTime = .zero

    // MARK: - Private State
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var pendingSeekTime: CMTime?
    private var isSeekInProgress = false

    // MARK: - Computed Properties
    var progress: Double {
        guard duration.seconds > 0 else { return 0 }
        return currentTime.seconds / duration.seconds
    }

    var currentTimeFormatted: String {
        formatTime(currentTime.seconds)
    }

    var durationFormatted: String {
        formatTime(duration.seconds)
    }

    // MARK: - Lifecycle

    func attach(to player: AVPlayer) {
        detach()
        self.player = player

        // Observe time updates
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time
            }
        }

        // Get duration when available
        Task {
            if let item = player.currentItem {
                let dur = try? await item.asset.load(.duration)
                self.duration = dur ?? .zero
            }
        }
    }

    func detach() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        player = nil
        currentTime = .zero
        duration = .zero
        isSeeking = false
        isSeekInProgress = false
        pendingSeekTime = nil
    }

    // MARK: - Seeking (Chase Pattern)

    /// Seek to absolute time using chase pattern
    /// Never cancels in-progress seeks; queues them instead
    func seek(to time: CMTime) {
        guard let player = player else { return }

        let clampedTime = clamp(time: time)

        if isSeekInProgress {
            // Queue this seek for when current one completes
            pendingSeekTime = clampedTime
            logger.debug("Queued seek to \(clampedTime.seconds)")
        } else {
            performSeek(to: clampedTime, player: player)
        }
    }

    /// Seek to percentage (0.0 - 1.0)
    func seek(toPercentage percentage: Double) {
        let clampedPercentage = max(0, min(1, percentage))
        let targetTime = CMTime(seconds: duration.seconds * clampedPercentage, preferredTimescale: duration.timescale)
        seek(to: targetTime)
    }

    /// Relative seek by seconds
    func step(by seconds: Double) {
        let targetTime = CMTime(seconds: currentTime.seconds + seconds, preferredTimescale: currentTime.timescale)
        seek(to: targetTime)
    }

    /// Step by predefined amount
    func step(_ step: SeekStep, forward: Bool) {
        let seconds = forward ? step.seconds : -step.seconds
        self.step(by: seconds)
    }

    /// Frame-accurate stepping
    func stepByFrame(forward: Bool) {
        guard let player = player,
              let currentItem = player.currentItem else { return }

        if forward {
            currentItem.step(byCount: 1)
        } else {
            currentItem.step(byCount: -1)
        }
    }

    // MARK: - Private Methods

    private func performSeek(to time: CMTime, player: AVPlayer) {
        isSeekInProgress = true
        isSeeking = true

        logger.debug("Seeking to \(time.seconds)")

        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self = self else { return }

                self.isSeekInProgress = false

                if let pending = self.pendingSeekTime {
                    // Process queued seek
                    self.pendingSeekTime = nil
                    if let player = self.player {
                        self.performSeek(to: pending, player: player)
                    }
                } else {
                    self.isSeeking = false
                }
            }
        }
    }

    private func clamp(time: CMTime) -> CMTime {
        let minTime = CMTime.zero
        let maxTime = duration

        if time < minTime {
            return minTime
        } else if time > maxTime {
            return maxTime
        }
        return time
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
