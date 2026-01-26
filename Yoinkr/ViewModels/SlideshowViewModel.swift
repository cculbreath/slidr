import SwiftUI
import Combine

@MainActor
@Observable
final class SlideshowViewModel {
    // MARK: - Configuration
    var imageDuration: TimeInterval = 5.0
    var gifDuration: TimeInterval = 10.0
    var isPlaying: Bool = true
    var loop: Bool = true

    // MARK: - State
    private(set) var items: [MediaItem] = []
    private(set) var currentIndex: Int = 0
    private var timerCancellable: AnyCancellable?

    var currentItem: MediaItem? {
        guard currentIndex >= 0 && currentIndex < items.count else { return nil }
        return items[currentIndex]
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

        if isPlaying {
            scheduleNextAdvance()
        }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
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

        if isPlaying {
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

        if isPlaying {
            scheduleNextAdvance()
        }
    }

    func goTo(index: Int) {
        timerCancellable?.cancel()
        currentIndex = max(0, min(index, items.count - 1))

        if isPlaying {
            scheduleNextAdvance()
        }
    }

    // MARK: - Playback Control

    func togglePlayback() {
        isPlaying.toggle()

        if isPlaying {
            scheduleNextAdvance()
        } else {
            timerCancellable?.cancel()
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
            duration = 0  // Videos handle their own advancement in Phase 2
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
