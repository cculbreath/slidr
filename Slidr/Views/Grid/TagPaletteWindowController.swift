import AppKit
import SwiftUI

@MainActor
final class TagPaletteWindowController: NSWindowController {
    private let viewModel: TagPaletteViewModel

    init(viewModel: TagPaletteViewModel) {
        self.viewModel = viewModel

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 350),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = "Tag Palette"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 220, height: 250)
        panel.setFrameAutosaveName("TagPalettePosition")
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let hostingView = NSHostingView(rootView: TagPaletteView(viewModel: viewModel))
        panel.contentView = hostingView

        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func toggle() {
        if isVisible {
            window?.orderOut(nil)
        } else {
            showWindow(nil)
            // Restore saved position; if no saved position, center on screen
            if window?.frameAutosaveName.isEmpty == false {
                // setFrameAutosaveName already restores position
            } else {
                window?.center()
            }
        }
    }
}
