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

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if window.toolbar !== coordinator.toolbar {
                window.toolbar = coordinator.toolbar
            }
            window.titleVisibility = .hidden

            // Find the NSSplitView for tracking separators
            if let splitView = findSplitView(in: window.contentView) {
                coordinator.splitView = splitView
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-check on updates in case the window changed
        guard let window = nsView.window else { return }
        if window.toolbar !== coordinator.toolbar {
            window.toolbar = coordinator.toolbar
        }
    }

    private func findSplitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let splitView = view as? NSSplitView {
            return splitView
        }
        for subview in view.subviews {
            if let found = findSplitView(in: subview) {
                return found
            }
        }
        return nil
    }
}
