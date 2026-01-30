import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var slideshowWindows: [NSWindow] = []
    private var controlWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {}

    func applicationWillTerminate(_ notification: Notification) {
        closeAllSlideshowWindows()
    }

    func openExternalSlideshow<Content: View>(
        on screen: NSScreen,
        content: Content,
        controlContent: AnyView? = nil,
        controlScreen: NSScreen? = nil
    ) {
        closeAllSlideshowWindows()
        let window = createSlideshowWindow(for: screen, content: content)
        slideshowWindows.append(window)

        if let controlContent, let controlScreen {
            controlWindow = createControlWindow(on: controlScreen, content: controlContent)
        }
    }

    func closeAllSlideshowWindows() {
        for window in slideshowWindows { window.close() }
        slideshowWindows.removeAll()
        controlWindow?.close()
        controlWindow = nil
    }

    private func createSlideshowWindow<Content: View>(for screen: NSScreen, content: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        let hostingView = NSHostingView(rootView: content)
        window.contentView = hostingView
        window.level = .screenSaver
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hostingView)
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
