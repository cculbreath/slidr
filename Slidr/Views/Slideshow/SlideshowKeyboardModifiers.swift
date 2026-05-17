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
// Only keys without a corresponding menu item live here. All other slideshow
// shortcuts are dispatched via the Slideshow menu (see SlidrCommands), which
// runs before the responder chain and so handles them globally for the
// slideshow scope.

struct SlideshowAltShortcutKeys: ViewModifier {
    let viewModel: SlideshowViewModel

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            switch press.key {
            case KeyEquivalent("j"):
                viewModel.previous()
                return .handled
            case KeyEquivalent("l"):
                viewModel.next()
                return .handled
            case KeyEquivalent("k"):
                viewModel.increaseVolume()
                return .handled
            default:
                return .ignored
            }
        }
    }
}
