import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var slideshowWindows: [NSWindow] = []
    private var controlWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {}

    func applicationWillTerminate(_ notification: Notification) {
        closeAllSlideshowWindows()
    }

    func openSlideshowOnAllMonitors<Content: View>(
        content: @escaping (NSScreen) -> Content,
        controlContent: (() -> AnyView)? = nil,
        controlOnSeparateMonitor: Bool = false
    ) {
        closeAllSlideshowWindows()
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let controlScreenIndex: Int?
        if controlOnSeparateMonitor && screens.count > 1 {
            controlScreenIndex = 1
        } else {
            controlScreenIndex = 0
        }

        for (index, screen) in screens.enumerated() {
            let isControlScreen = index == controlScreenIndex
            let window = createSlideshowWindow(
                for: screen,
                content: content(screen),
                showControls: isControlScreen || !controlOnSeparateMonitor
            )
            slideshowWindows.append(window)
        }

        if controlOnSeparateMonitor, let controlContent = controlContent, screens.count > 1 {
            let controlScreen = screens[controlScreenIndex ?? 0]
            controlWindow = createControlWindow(on: controlScreen, content: controlContent())
        }
    }

    func openSlideshowOnScreen<Content: View>(_ screen: NSScreen, content: Content) {
        closeAllSlideshowWindows()
        let window = createSlideshowWindow(for: screen, content: content, showControls: true)
        slideshowWindows.append(window)
    }

    func closeAllSlideshowWindows() {
        for window in slideshowWindows { window.close() }
        slideshowWindows.removeAll()
        controlWindow?.close()
        controlWindow = nil
    }

    private func createSlideshowWindow<Content: View>(for screen: NSScreen, content: Content, showControls: Bool) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = NSHostingView(rootView: content)
        window.level = .screenSaver
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        return window
    }

    private func createControlWindow(on screen: NSScreen, content: AnyView) -> NSWindow {
        let windowSize = CGSize(width: 400, height: 200)
        let origin = CGPoint(x: screen.frame.midX - windowSize.width / 2, y: screen.frame.minY + 50)
        let window = NSWindow(
            contentRect: CGRect(origin: origin, size: windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = NSHostingView(rootView: content)
        window.title = "Slideshow Controls"
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.makeKeyAndOrderFront(nil)
        return window
    }

    var availableScreens: [NSScreen] { NSScreen.screens }
    var primaryScreen: NSScreen? { NSScreen.main ?? NSScreen.screens.first }
}

// MARK: - Notification Names

extension Notification.Name {
    static let startSlideshow = Notification.Name("com.slidr.startSlideshow")
    static let stopSlideshow = Notification.Name("com.slidr.stopSlideshow")
    static let slideshowNext = Notification.Name("com.slidr.slideshowNext")
    static let slideshowPrevious = Notification.Name("com.slidr.slideshowPrevious")
}
