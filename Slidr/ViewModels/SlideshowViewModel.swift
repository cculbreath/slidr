import SwiftUI
import Combine
import AVFoundation

// MARK: - Video Play Duration

enum VideoPlayDuration: Hashable {
    case slideshowTimer
    case fullVideo
    case fixed(TimeInterval)

    var isFullVideo: Bool {
        if case .fullVideo = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .slideshowTimer: return "Slideshow Timer Duration"
        case .fullVideo: return "Full Video Duration"
        case .fixed(let seconds):
            if seconds < 60 {
                return "\(Int(seconds)) sec"
            } else {
                return "\(Int(seconds / 60)) min"
            }
        }
    }

    static let presets: [VideoPlayDuration] = [
        .slideshowTimer, .fullVideo,
        .fixed(5), .fixed(15), .fixed(30),
        .fixed(60), .fixed(300), .fixed(600)
    ]
}

@MainActor
@Observable
final class SlideshowViewModel {
    // MARK: - Configuration
    var slideDuration: TimeInterval = 5.0
    var isPlaying: Bool = false
    var loop: Bool = true
    var videoPlayDuration: VideoPlayDuration = .fixed(30)
    var randomizeClipLocation: Bool = false
    var playFullGIF: Bool = false
    var showCaptions: Bool = false
    var showSubtitles: Bool = false

    // MARK: - Video Configuration
    var volume: Float = 1.0
    var isMuted: Bool = false
    let scrubber = SmoothScrubber()

    // MARK: - Playback Mode
    var isRandomMode: Bool = false
    private var originalOrder: [MediaItem] = []
    private var shuffledOrder: [MediaItem] = []

    // MARK: - Pre-buffering
    struct PreloadedMedia {
        let image: NSImage?
        let videoAsset: AVAsset?
    }

    private var preloadedItems: [UUID: PreloadedMedia] = [:]

    // MARK: - Timer Progress
    var showTimerBar: Bool = false
    private(set) var timerStartDate: Date?
    private(set) var currentSlideDuration: TimeInterval = 0
    private(set) var pausedTimerProgress: Double = 0

    // MARK: - State
    private(set) var items: [MediaItem] = []
    private(set) var currentIndex: Int = 0
    private var timerCancellable: AnyCancellable?
    private(set) var library: MediaLibrary?

    var activeItems: [MediaItem] {
        isRandomMode && !shuffledOrder.isEmpty ? shuffledOrder : items
    }

    var currentItem: MediaItem? {
        let active = activeItems
        guard currentIndex >= 0 && currentIndex < active.count else { return nil }
        return active[currentIndex]
    }

    var currentItemIsVideo: Bool {
        currentItem?.isVideo ?? false
    }

    var currentItemHasAudio: Bool {
        currentItem?.hasAudio ?? false
    }

    var hasNext: Bool {
        currentIndex < activeItems.count - 1 || loop
    }

    var hasPrevious: Bool {
        currentIndex > 0 || loop
    }

    var progress: Double {
        guard !activeItems.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(activeItems.count)
    }

    // MARK: - Setup

    func start(with items: [MediaItem], startingAt index: Int = 0) {
        self.items = items
        self.currentIndex = max(0, min(index, items.count - 1))

        if isPlaying {
            scheduleNextAdvance()
        }

        Task { await preloadAdjacentItems() }
    }

    func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        scrubber.detach()
        items = []
        currentIndex = 0
        resetTimerProgress()
    }

    private func resetTimerProgress() {
        timerStartDate = nil
        currentSlideDuration = 0
        pausedTimerProgress = 0
    }

    // MARK: - Navigation

    func next() {
        timerCancellable?.cancel()
        resetTimerProgress()

        let count = activeItems.count
        if currentIndex < count - 1 {
            currentIndex += 1
        } else if loop {
            currentIndex = 0
        }

        if isPlaying {
            scheduleNextAdvance()
        }

        Task { await preloadAdjacentItems() }
    }

    func previous() {
        timerCancellable?.cancel()
        resetTimerProgress()

        let count = activeItems.count
        if currentIndex > 0 {
            currentIndex -= 1
        } else if loop {
            currentIndex = count - 1
        }

        if isPlaying {
            scheduleNextAdvance()
        }

        Task { await preloadAdjacentItems() }
    }

    func goTo(index: Int) {
        timerCancellable?.cancel()
        currentIndex = max(0, min(index, activeItems.count - 1))

        if isPlaying {
            scheduleNextAdvance()
        }
    }

    // MARK: - Playback Control

    func togglePlayback() {
        isPlaying.toggle()

        if isPlaying {
            // Resume: adjust timerStartDate to account for already-elapsed progress
            if pausedTimerProgress > 0, currentSlideDuration > 0 {
                let remaining = currentSlideDuration * (1.0 - pausedTimerProgress)
                timerStartDate = Date()
                currentSlideDuration = remaining
                pausedTimerProgress = 0
                timerCancellable = Timer.publish(every: remaining, on: .main, in: .common)
                    .autoconnect()
                    .first()
                    .sink { [weak self] _ in
                        self?.next()
                    }
            } else {
                scheduleNextAdvance()
            }
        } else {
            // Pause: capture current progress
            if let start = timerStartDate, currentSlideDuration > 0 {
                let elapsed = Date().timeIntervalSince(start)
                pausedTimerProgress = min(1.0, elapsed / currentSlideDuration)
            }
            timerCancellable?.cancel()
            timerStartDate = nil
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
        if videoPlayDuration.isFullVideo && isPlaying {
            next()
        }
        // For non-fullVideo modes, the slide timer handles advancement
    }

    private func scheduleNextAdvance() {
        guard let item = currentItem else { return }

        let duration: TimeInterval

        switch item.mediaType {
        case .image:
            duration = slideDuration
        case .gif:
            if playFullGIF, let gifLoopDuration = item.duration, gifLoopDuration > 0 {
                duration = max(gifLoopDuration, slideDuration)
            } else {
                duration = slideDuration
            }
        case .video:
            configureClipRegion(for: item)
            if videoPlayDuration.isFullVideo { return } // Video end triggers advance
            duration = effectiveVideoDuration()
        }

        guard duration > 0 else { return }

        currentSlideDuration = duration
        timerStartDate = Date()
        pausedTimerProgress = 0

        timerCancellable = Timer.publish(every: duration, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { [weak self] _ in
                self?.next()
            }
    }

    private func effectiveVideoDuration() -> TimeInterval {
        switch videoPlayDuration {
        case .slideshowTimer: return slideDuration
        case .fullVideo: return 0
        case .fixed(let seconds): return seconds
        }
    }

    private func configureClipRegion(for item: MediaItem) {
        guard !videoPlayDuration.isFullVideo else {
            scrubber.clearClipRegion()
            return
        }

        let playDuration = effectiveVideoDuration()

        if randomizeClipLocation,
           let videoDuration = item.duration,
           videoDuration > playDuration {
            let maxOffset = videoDuration - playDuration
            let randomOffset = Double.random(in: 0...maxOffset)
            let seekTime = CMTime(seconds: randomOffset, preferredTimescale: 600)
            scrubber.setClipRegion(start: randomOffset, duration: playDuration, initialSeek: seekTime)
        } else {
            scrubber.setClipRegion(start: 0, duration: playDuration)
        }
    }

    // MARK: - Settings & Library

    private(set) var settings: AppSettings?

    func configure(settings: AppSettings) {
        self.settings = settings
        slideDuration = settings.defaultImageDuration
        loop = settings.loopSlideshow
        isRandomMode = settings.shuffleSlideshow
        videoPlayDuration = settings.videoPlayDuration
        randomizeClipLocation = settings.randomizeClipLocation
        playFullGIF = settings.playFullGIF
        volume = settings.defaultVolume
        isMuted = settings.muteByDefault
        showCaptions = settings.showCaptions
        showSubtitles = settings.showSubtitles
        showTimerBar = settings.showTimerBar
    }

    func persistToSettings() {
        guard let settings else { return }
        settings.defaultImageDuration = slideDuration
        settings.loopSlideshow = loop
        settings.shuffleSlideshow = isRandomMode
        settings.videoPlayDuration = videoPlayDuration
        settings.randomizeClipLocation = randomizeClipLocation
        settings.playFullGIF = playFullGIF
        settings.defaultVolume = volume
        settings.muteByDefault = isMuted
        settings.showCaptions = showCaptions
        settings.showSubtitles = showSubtitles
        settings.showTimerBar = showTimerBar
    }

    func configure(library: MediaLibrary) {
        self.library = library
    }

    // MARK: - Pre-buffering

    func preloadAdjacentItems() async {
        guard let library = library else { return }
        let active = activeItems
        let indicesToPreload = [
            currentIndex - 1,
            currentIndex + 1
        ].filter { $0 >= 0 && $0 < active.count }

        for index in indicesToPreload {
            let item = active[index]
            guard preloadedItems[item.id] == nil else { continue }
            await preloadItem(item, library: library)
        }

        let adjacentIDs = Set(indicesToPreload.map { active[$0].id })
        let currentID = currentItem?.id
        preloadedItems = preloadedItems.filter { key, _ in
            adjacentIDs.contains(key) || key == currentID
        }
    }

    private func preloadItem(_ item: MediaItem, library: MediaLibrary) async {
        let url = library.absoluteURL(for: item)

        switch item.mediaType {
        case .image, .gif:
            if let image = NSImage(contentsOf: url) {
                preloadedItems[item.id] = PreloadedMedia(image: image, videoAsset: nil)
            }
        case .video:
            let asset = AVURLAsset(url: url)
            preloadedItems[item.id] = PreloadedMedia(image: nil, videoAsset: asset)
        }
    }

    func preloadedMedia(for item: MediaItem) -> PreloadedMedia? {
        preloadedItems[item.id]
    }

    // MARK: - Rating

    func rateCurrentItem(_ rating: Int) {
        guard let item = currentItem else { return }
        item.rating = rating > 0 ? rating : nil
    }

    // MARK: - Random Mode

    func toggleRandomMode() {
        isRandomMode.toggle()
        if isRandomMode {
            originalOrder = items
            shuffledOrder = items.shuffled()
            currentIndex = 0
        } else {
            if let current = currentItem,
               let newIndex = originalOrder.firstIndex(where: { $0.id == current.id }) {
                currentIndex = newIndex
            }
            shuffledOrder = []
        }
    }

    // MARK: - Volume

    func increaseVolume() {
        volume = min(1.0, volume + 0.1)
    }

    func decreaseVolume() {
        volume = max(0.0, volume - 0.1)
    }
}
