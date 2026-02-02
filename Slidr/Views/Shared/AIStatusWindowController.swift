import AppKit
import SwiftUI

@MainActor
final class AIStatusWindowController: NSWindowController {
    private let coordinator: AIProcessingCoordinator
    private var autoDismissTask: Task<Void, Never>?

    init(coordinator: AIProcessingCoordinator) {
        self.coordinator = coordinator

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = "AI Status"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 300, height: 160)
        panel.setFrameAutosaveName("AIStatusPosition")
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let hostingView = NSHostingView(
            rootView: AIStatusView(onDismiss: { [weak panel] in
                panel?.orderOut(nil)
            })
            .environment(coordinator)
        )
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

    func show() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        showWindow(nil)
    }

    func toggle() {
        if isVisible {
            window?.orderOut(nil)
        } else {
            show()
        }
    }

    func scheduleAutoDismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard !coordinator.isProcessing else { return }
            // Only auto-dismiss if no errors
            let hasErrors = coordinator.operationLog.contains {
                if case .failure = $0.status { return true }
                return false
            }
            if !hasErrors {
                window?.orderOut(nil)
            }
        }
    }
}
