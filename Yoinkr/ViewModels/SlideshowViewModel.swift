import SwiftUI
import Combine
import AVFoundation

@MainActor
@Observable
final class SlideshowViewModel {
    // MARK: - Configuration
    var imageDuration: TimeInterval = 5.0
    var gifDuration: TimeInterval = 10.0
    var isPlaying: Bool = true
    var loop: Bool = true

    // MARK: - Video Configuration
    var volume: Float = 1.0
    var isMuted: Bool = false
    let scrubber = SmoothScrubber()

    // MARK: - State
    private(set) var items: [MediaItem] = []
    private(set) var currentIndex: Int = 0
    private var timerCancellable: AnyCancellable?

    var currentItem: MediaItem? {
        guard currentIndex >= 0 && currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var currentItemIsVideo: Bool {
        currentItem?.isVideo ?? false
    }

    var currentItemHasAudio: Bool {
        currentItem?.hasAudio ?? false
    }

    var hasNext: Bool {
        currentIndex < items.count - 1 || loop
    }

    var hasPrevious: Bool {
        currentIndex > 0 || loop
    }

    var progress: Double {
        guard !items.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(items.count)
    }

    // MARK: - Setup

    func start(with items: [MediaItem], startingAt index: Int = 0) {
        self.items = items
        self.currentIndex = max(0, min(index, items.count - 1))

        if isPlaying && !currentItemIsVideo {
            scheduleNextAdvance()
        }
        // Videos handle their own advancement via onVideoEnded callback
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        scrubber.detach()
        items = []
        currentIndex = 0
    }

    // MARK: - Navigation

    func next() {
        timerCancellable?.cancel()

        if currentIndex < items.count - 1 {
            currentIndex += 1
        } else if loop {
            currentIndex = 0
        }

        if isPlaying && !currentItemIsVideo {
            scheduleNextAdvance()
        }
    }

    func previous() {
        timerCancellable?.cancel()

        if currentIndex > 0 {
            currentIndex -= 1
        } else if loop {
            currentIndex = items.count - 1
        }

        if isPlaying && !currentItemIsVideo {
            scheduleNextAdvance()
        }
    }

    func goTo(index: Int) {
        timerCancellable?.cancel()
        currentIndex = max(0, min(index, items.count - 1))

        if isPlaying && !currentItemIsVideo {
            scheduleNextAdvance()
        }
    }

    // MARK: - Playback Control

    func togglePlayback() {
        isPlaying.toggle()

        if isPlaying && !currentItemIsVideo {
            scheduleNextAdvance()
        } else if !isPlaying {
            timerCancellable?.cancel()
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }

    // MARK: - Video Seeking

    func seekVideo(by step: SeekStep, forward: Bool) {
        guard currentItemIsVideo else { return }
        scrubber.step(step, forward: forward)
    }

    func stepVideoFrame(forward: Bool) {
        guard currentItemIsVideo else { return }
        scrubber.stepByFrame(forward: forward)
    }

    // Called by VideoPlayerView when video ends
    func onVideoEnded() {
        if isPlaying {
            next()
        }
    }

    private func scheduleNextAdvance() {
        guard let item = currentItem else { return }

        let duration: TimeInterval
        switch item.mediaType {
        case .image:
            duration = imageDuration
        case .gif:
            duration = gifDuration
        case .video:
            return  // Videos handle their own advancement
        }

        guard duration > 0 else { return }

        timerCancellable = Timer.publish(every: duration, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { [weak self] _ in
                self?.next()
            }
    }
}
