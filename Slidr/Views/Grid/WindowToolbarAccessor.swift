import AppKit
import SwiftUI

// MARK: - WindowToolbarModifier

struct WindowToolbarModifier: ViewModifier {
    let coordinator: GridToolbarCoordinator

    func body(content: Content) -> some View {
        content.background(WindowToolbarAccessor(coordinator: coordinator))
    }
}

// MARK: - WindowToolbarAccessor

struct WindowToolbarAccessor: NSViewRepresentable {
    let coordinator: GridToolbarCoordinator

    func makeNSView(context: Context) -> ToolbarGuardView {
        let view = ToolbarGuardView()
        view.coordinator = coordinator
        return view
    }

    func updateNSView(_ nsView: ToolbarGuardView, context: Context) {
        nsView.coordinator = coordinator
        nsView.reinstallIfNeeded()
    }
}

// MARK: - ToolbarGuardView

/// Installs a custom NSToolbar on the host window and guards it against
/// SwiftUI's NavigationSplitView overwriting it during view reconciliation.
/// Uses KVO on NSWindow.toolbar to detect and counteract SwiftUI's changes.
final class ToolbarGuardView: NSView {
    var coordinator: GridToolbarCoordinator?
    private var observation: NSKeyValueObservation?
    private var isSettingToolbar = false
    private var guardCount = 0
    private let maxGuardAttempts = 20

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observation = nil
        guardCount = 0

        guard let window else { return }
        installToolbar(on: window)

        // Watch for SwiftUI overwriting our toolbar during view reconciliation.
        // Re-assert the custom toolbar each time, up to maxGuardAttempts.
        observation = window.observe(\.toolbar, options: [.new]) { [weak self] window, _ in
            DispatchQueue.main.async {
                guard let self,
                      !self.isSettingToolbar,
                      self.guardCount < self.maxGuardAttempts else { return }
                self.guardCount += 1
                self.installToolbar(on: window)
            }
        }
    }

    func reinstallIfNeeded() {
        guard let window, let coordinator else { return }
        if window.toolbar !== coordinator.toolbar {
            installToolbar(on: window)
        }
    }

    private func installToolbar(on window: NSWindow) {
        guard let coordinator else { return }
        isSettingToolbar = true
        if window.toolbar !== coordinator.toolbar {
            window.toolbar = coordinator.toolbar
        }
        window.titleVisibility = .hidden
        isSettingToolbar = false

        // Find the NSSplitView after toolbar installation so separators
        // remain plain spacer items (no hard section boundaries).
        if coordinator.splitView == nil,
           let splitView = Self.findSplitView(in: window.contentView) {
            coordinator.splitView = splitView
        }
    }

    private static func findSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let splitView = view as? NSSplitView { return splitView }
        for subview in view.subviews {
            if let found = findSplitView(in: subview) { return found }
        }
        return nil
    }
}
