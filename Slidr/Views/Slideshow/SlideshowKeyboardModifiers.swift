import SwiftUI

// MARK: - Toggle Glow

private let glowColor = Color.cyan

extension View {
    func toggleGlow(_ isOn: Bool) -> some View {
        self
            .foregroundStyle(isOn ? glowColor : .white.opacity(0.4))
            .shadow(color: isOn ? glowColor.opacity(0.7) : .clear, radius: 6)
            .shadow(color: isOn ? glowColor.opacity(0.4) : .clear, radius: 12)
            .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

// MARK: - Keyboard Modifiers

/// Composed keyboard modifier to keep body expression manageable
struct SlideshowKeyboardModifier: ViewModifier {
    let viewModel: SlideshowViewModel
    let onDismiss: () -> Void
    let goNext: () -> Void
    let goPrevious: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(BasicNavigationKeys(onDismiss: onDismiss, goNext: goNext, goPrevious: goPrevious, togglePlayback: { viewModel.togglePlayback() }))
            .modifier(ArrowKeys(viewModel: viewModel, goNext: goNext, goPrevious: goPrevious))
            .modifier(VolumeKeys(viewModel: viewModel))
    }
}

private struct BasicNavigationKeys: ViewModifier {
    let onDismiss: () -> Void
    let goNext: () -> Void
    let goPrevious: () -> Void
    let togglePlayback: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.space) {
                togglePlayback()
                return .handled
            }
            .onKeyPress(.escape) {
                onDismiss()
                return .handled
            }
    }
}

private struct ArrowKeys: ViewModifier {
    let viewModel: SlideshowViewModel
    let goNext: () -> Void
    let goPrevious: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: .down) { press in
                handleArrowKey(press)
            }
    }

    private func handleArrowKey(_ press: KeyPress) -> KeyPress.Result {
        let hasShift = press.modifiers.contains(.shift)
        let hasOption = press.modifiers.contains(.option)

        // Shift + arrow = seek 5s
        if press.key == .rightArrow && hasShift {
            viewModel.seekVideo(by: .fiveSeconds, forward: true)
            return .handled
        }
        if press.key == .leftArrow && hasShift {
            viewModel.seekVideo(by: .fiveSeconds, forward: false)
            return .handled
        }
        // Option + arrow = seek 30s
        if press.key == .rightArrow && hasOption {
            viewModel.seekVideo(by: .thirtySeconds, forward: true)
            return .handled
        }
        if press.key == .leftArrow && hasOption {
            viewModel.seekVideo(by: .thirtySeconds, forward: false)
            return .handled
        }
        // Plain arrow = next/previous
        if press.key == .rightArrow {
            goNext()
            return .handled
        }
        if press.key == .leftArrow {
            goPrevious()
            return .handled
        }
        // Comma = step frame backward
        if press.key == KeyEquivalent(",") {
            viewModel.stepVideoFrame(forward: false)
            return .handled
        }
        // Period = step frame forward
        if press.key == KeyEquivalent(".") {
            viewModel.stepVideoFrame(forward: true)
            return .handled
        }
        return .ignored
    }
}

private struct VolumeKeys: ViewModifier {
    let viewModel: SlideshowViewModel

    func body(content: Content) -> some View {
        content
            .onKeyPress(phases: .down) { press in
                handleVolumeKey(press)
            }
    }

    private func handleVolumeKey(_ press: KeyPress) -> KeyPress.Result {
        // M = mute toggle
        if press.key == KeyEquivalent("m") {
            viewModel.toggleMute()
            return .handled
        }
        // Up arrow = volume up
        if press.key == .upArrow {
            viewModel.increaseVolume()
            return .handled
        }
        // K = volume up
        if press.key == KeyEquivalent("k") {
            viewModel.increaseVolume()
            return .handled
        }
        // Down arrow = volume down
        if press.key == .downArrow {
            viewModel.decreaseVolume()
            return .handled
        }
        return .ignored
    }
}

struct CaptionKeys: ViewModifier {
    @Bindable var viewModel: SlideshowViewModel

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            if press.key == KeyEquivalent("c") {
                viewModel.showCaptions.toggle()
                return .handled
            }
            return .ignored
        }
    }
}

struct RatingKeys: ViewModifier {
    let viewModel: SlideshowViewModel
    let uiState: SlideshowUIState

    func body(content: Content) -> some View {
        content
            .onKeyPress("0") { rateItem(0); return .handled }
            .onKeyPress("1") { rateItem(1); return .handled }
            .onKeyPress("2") { rateItem(2); return .handled }
            .onKeyPress("3") { rateItem(3); return .handled }
            .onKeyPress("4") { rateItem(4); return .handled }
            .onKeyPress("5") { rateItem(5); return .handled }
    }

    private func rateItem(_ rating: Int) {
        viewModel.rateCurrentItem(rating)
        uiState.ratingFeedback = rating
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            uiState.ratingFeedback = nil
        }
    }
}

struct ExtraNavigationKeys: ViewModifier {
    @Bindable var viewModel: SlideshowViewModel
    let uiState: SlideshowUIState

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            handleKey(press)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case KeyEquivalent("i"):
            uiState.showInfoOverlay.toggle()
            return .handled
        case KeyEquivalent("r"):
            viewModel.toggleRandomMode()
            return .handled
        case KeyEquivalent("f"):
            if let window = NSApplication.shared.keyWindow {
                window.toggleFullScreen(nil)
            }
            return .handled
        case KeyEquivalent("s"):
            viewModel.showSubtitles.toggle()
            return .handled
        case KeyEquivalent("t"):
            viewModel.showTimerBar.toggle()
            return .handled
        case KeyEquivalent("l"):
            viewModel.next()
            return .handled
        case KeyEquivalent("j"):
            viewModel.previous()
            return .handled
        default:
            return .ignored
        }
    }
}
