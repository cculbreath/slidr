import SwiftUI
import AppKit

/// Shared UI state for slideshow views, extracted from SlideshowView to reduce its size
/// and allow child views to read/modify state without binding gymnastics.
@MainActor
@Observable
final class SlideshowUIState {
    // MARK: - Control Visibility

    var showControls = false
    var hideControlsTask: Task<Void, Never>?
    var showTimerPopover = false
    var showVideoPopover = false
    var isDraggingControls = false
    var controlsOffset: CGSize = .zero
    var controlsDragOffset: CGSize = .zero
    var lastMouseLocation: CGPoint = .zero

    // MARK: - Overlays

    var showInfoOverlay = false
    var isFullscreen = false
    var ratingFeedback: Int?

    // MARK: - Video Captions

    var showVideoCaptions = false
    var videoCaptionTask: Task<Void, Never>?

    // MARK: - Scrub Mode

    var isScrubModeActive = false
    var scrubThumbnails: [NSImage] = []
    var scrubPosition: CGFloat = 0
    var wasPlayingBeforeScrub = false
    var optionKeyMonitor: Any?

    // MARK: - Computed

    var isAnyPopoverOpen: Bool {
        showTimerPopover || showVideoPopover
    }

    // MARK: - Methods

    func showControlsTemporarily() {
        showControls = true
        scheduleHideControls()
    }

    func scheduleHideControls() {
        hideControlsTask?.cancel()
        guard !isAnyPopoverOpen && !isDraggingControls else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled && !isAnyPopoverOpen && !isDraggingControls {
                showControls = false
            }
        }
    }
}
