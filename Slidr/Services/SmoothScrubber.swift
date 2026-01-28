import Foundation
import AVFoundation
import OSLog

@MainActor
@Observable
final class SmoothScrubber {
    // MARK: - Published State
    private(set) var isSeeking = false
    private(set) var currentTime: CMTime = .zero
    private(set) var duration: CMTime = .zero

    // MARK: - Clip Region
    private(set) var clipStartSeconds: Double = 0
    private(set) var clipDurationSeconds: Double? = nil

    var hasClipRegion: Bool { clipDurationSeconds != nil }

    var clipStartFraction: Double {
        guard duration.seconds > 0 else { return 0 }
        return max(0, min(1.0, clipStartSeconds / duration.seconds))
    }

    var clipLengthFraction: Double {
        guard let clipDur = clipDurationSeconds, duration.seconds > 0 else { return 1 }
        return max(0, min(clipDur / duration.seconds, 1.0 - clipStartFraction))
    }

    // MARK: - Private State
    private weak var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var pendingSeekTime: CMTime?
    private var initialSeekTime: CMTime?
    private var isSeekInProgress = false

    // MARK: - Computed Properties
    var progress: Double {
        guard duration.seconds > 0 else { return 0 }
        return max(0, min(1.0, currentTime.seconds / duration.seconds))
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

        // Observe player item status — load duration once readyToPlay
        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in
                // Try synchronous duration first
                let dur = item.duration
                if dur.isValid && !dur.isIndefinite && dur.seconds > 0 {
                    self?.duration = dur
                } else {
                    // Fallback: async load from the asset
                    if let loaded = try? await item.asset.load(.duration) {
                        self?.duration = loaded
                    }
                }

                // Execute any queued initial seek (e.g. randomized clip start)
                if let seekTime = self?.initialSeekTime {
                    self?.initialSeekTime = nil
                    self?.seek(to: seekTime)
                }
            }
        }
    }

    /// Only detach if still attached to the given player.
    /// Prevents a disappearing view from detaching a newly attached player.
    func detach(from player: AVPlayer) {
        guard self.player === player else { return }
        detach()
    }

    func detach() {
        statusObservation?.invalidate()
        statusObservation = nil
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
        initialSeekTime = nil
        clipStartSeconds = 0
        clipDurationSeconds = nil
    }

    // MARK: - Clip Region

    func setClipRegion(start: Double, duration: Double) {
        clipStartSeconds = start
        clipDurationSeconds = duration
    }

    func clearClipRegion() {
        clipStartSeconds = 0
        clipDurationSeconds = nil
    }

    // MARK: - Seeking (Chase Pattern)

    /// Seek to absolute time using chase pattern
    /// Never cancels in-progress seeks; queues them instead
    func seek(to time: CMTime) {
        guard let player = player else {
            // Player not attached yet — queue for execution after attach + readyToPlay
            initialSeekTime = time
            return
        }

        let clampedTime = clamp(time: time)

        if isSeekInProgress {
            // Queue this seek for when current one completes
            pendingSeekTime = clampedTime
            Logger.scrubber.debug("Queued seek to \(clampedTime.seconds)")
        } else {
            performSeek(to: clampedTime, player: player)
        }
    }

    /// Seek to percentage (0.0 - 1.0)
    func seek(toPercentage percentage: Double) {
        let clampedPercentage = max(0, min(1, percentage))
        let targetTime = CMTime(seconds: duration.seconds * clampedPercentage, preferredTimescale: 600)
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

        Logger.scrubber.debug("Seeking to \(time.seconds)")

        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self else { return }
            Task { @MainActor in
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
