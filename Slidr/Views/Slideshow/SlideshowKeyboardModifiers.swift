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

// MARK: - Alt Shortcut Keys
//
// Most slideshow shortcuts are dispatched via the Slideshow menu (see
// SlidrCommands), which runs before the responder chain. But the menu's
// .keyboardShortcut routing depends on the focused-scene value being set,
// which in turn requires the slideshow view to actually hold keyboard focus.
// If focus has drifted (toolbar, sidebar, etc.) the menu shortcut is gated
// off — so we also handle the critical "I'm stuck" keys (Esc / Space /
// arrows) here as an in-view safety net. AppKit menu dispatch runs first
// when focus is on the slideshow, so this doesn't double-fire.

struct SlideshowAltShortcutKeys: ViewModifier {
    let viewModel: SlideshowViewModel
    let onDismiss: () -> Void
    let goNext: () -> Void
    let goPrevious: () -> Void
    let onRate: (Int) -> Void
    let onDeleteCurrent: () -> Void

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            // Cmd+Delete: trash the current item.
            if press.key == .delete, press.modifiers.contains(.command) {
                onDeleteCurrent()
                return .handled
            }
            switch press.key {
            case .escape:
                onDismiss()
                return .handled
            case .space:
                viewModel.togglePlayback()
                return .handled
            case .leftArrow:
                goPrevious()
                return .handled
            case .rightArrow:
                goNext()
                return .handled
            case KeyEquivalent("j"):
                viewModel.previous()
                return .handled
            case KeyEquivalent("l"):
                viewModel.next()
                return .handled
            case KeyEquivalent("k"):
                viewModel.increaseVolume()
                return .handled
            case KeyEquivalent("0"):
                onRate(0); return .handled
            case KeyEquivalent("1"):
                onRate(1); return .handled
            case KeyEquivalent("2"):
                onRate(2); return .handled
            case KeyEquivalent("3"):
                onRate(3); return .handled
            case KeyEquivalent("4"):
                onRate(4); return .handled
            case KeyEquivalent("5"):
                onRate(5); return .handled
            default:
                return .ignored
            }
        }
    }
}
