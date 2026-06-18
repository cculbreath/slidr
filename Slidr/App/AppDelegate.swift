import AppKit
import SwiftUI
import OSLog

extension Notification.Name {
    static let slidrImportURLs = Notification.Name("SlidrImportURLs")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var slideshowWindows: [NSWindow] = []
    private var controlWindow: NSWindow?
    private(set) var pendingImportURLs: [URL] = []
    private(set) var pendingServiceImportURLs: [URL] = []
    private var aiStatusWindowController: AIStatusWindowController?

    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "Services")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register as the provider for the "Copy to Slidr Library" Services menu item.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// The single, app-lifetime AI status window, created on first use. Owned
    /// here rather than in a ContentView `@State` so exactly one panel exists no
    /// matter how many times a window is opened or ContentView is rebuilt (e.g.
    /// across vault lock/unlock) — otherwise orphaned panels stack up.
    @MainActor
    func aiStatusWindow(for coordinator: AIProcessingCoordinator) -> AIStatusWindowController {
        if let existing = aiStatusWindowController {
            return existing
        }
        let controller = AIStatusWindowController(coordinator: coordinator)
        aiStatusWindowController = controller
        return controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeAllSlideshowWindows()
    }

    // MARK: - Dock / Finder file drops

    func application(_ application: NSApplication, open urls: [URL]) {
        let filtered = urls.filter { url in
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return true
            }
            return FileTypeDetector.isSupported(url)
        }
        guard !filtered.isEmpty else { return }
        pendingImportURLs.append(contentsOf: filtered)
        NotificationCenter.default.post(name: .slidrImportURLs, object: nil)
    }

    func consumePendingImportURLs() -> [URL] {
        let urls = pendingImportURLs
        pendingImportURLs.removeAll()
        return urls
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
        window.collectionBehavior = [.canJoinAllSpaces]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(hostingView)
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

// MARK: - Services Menu ("Copy to Slidr Library")

extension AppDelegate {
    /// Handles the "Copy to Slidr Library" Services menu item. Invoked by the
    /// system (selector `addToSlidr:userData:error:`) with whatever the source
    /// app placed on the pasteboard: file URLs from Finder, an image's web
    /// address from a browser, or raw image data.
    @objc func addToSlidr(_ pboard: NSPasteboard,
                          userData: String?,
                          error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        logPasteboardInventory(pboard)   // TEMP: confirm what browsers actually provide

        // Finder file selections — import the originals directly (copied into the
        // library by the forced-copy import path).
        let fileURLs = (pboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let importableFiles = fileURLs.filter { isImportable($0) }
        if !importableFiles.isEmpty {
            enqueueServiceImport(importableFiles)
        }

        // Browser content: an image's web address and/or raw image data. Capture
        // the pasteboard data now — the pasteboard is only valid during this call.
        let webURLs = webMediaURLCandidates(from: pboard)
        let pasteboardImage = bestImageData(from: pboard)

        guard !webURLs.isEmpty || pasteboardImage != nil else { return }

        Task { [weak self] in
            var downloaded: [URL] = []
            for url in webURLs {
                if let temp = await Self.downloadMedia(from: url) {
                    downloaded.append(temp)
                }
            }
            // Fall back to the pasteboard image only if the URL(s) yielded nothing —
            // downloading the original source preserves animated GIFs, whereas
            // pasteboard image data is often a rasterized still.
            if downloaded.isEmpty, let pasteboardImage,
               let temp = Self.writeTempFile(data: pasteboardImage.data, ext: pasteboardImage.ext) {
                downloaded.append(temp)
            }
            guard !downloaded.isEmpty else { return }
            await MainActor.run { self?.enqueueServiceImport(downloaded) }
        }
    }

    func consumePendingServiceImportURLs() -> [URL] {
        let urls = pendingServiceImportURLs
        pendingServiceImportURLs.removeAll()
        return urls
    }

    private func enqueueServiceImport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pendingServiceImportURLs.append(contentsOf: urls)
        NotificationCenter.default.post(name: .slidrImportURLs, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.logger.info("Queued \(urls.count) item(s) from Services for import")
    }

    private func isImportable(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return true
        }
        return FileTypeDetector.isSupported(url)
    }

    /// Gathers candidate http(s) media URLs from the pasteboard. Safari usually
    /// provides a clean URL object; Chrome typically omits that but embeds the
    /// image inside an HTML fragment (`<img src>`) or as plain text. Pulling the
    /// source URL out and downloading it preserves the original (animated GIFs).
    private func webMediaURLCandidates(from pboard: NSPasteboard) -> [URL] {
        var candidates: [URL] = []

        // 1. Explicit URL object(s).
        let urlObjects = (pboard.readObjects(forClasses: [NSURL.self], options: [:]) as? [URL]) ?? []
        candidates.append(contentsOf: urlObjects.filter { !$0.isFileURL })

        // 2. HTML fragment with an <img src> (Chrome).
        if let html = pboard.string(forType: .html), let src = firstImageSource(inHTML: html) {
            candidates.append(contentsOf: [URL(string: src)].compactMap { $0 })
        }

        // 3. Plain text that is itself an http(s) URL.
        if let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: text) {
            candidates.append(url)
        }

        // Keep only http(s), de-duplicated, order preserved.
        var seen = Set<String>()
        return candidates.filter { url in
            guard url.scheme == "http" || url.scheme == "https" else { return false }
            return seen.insert(url.absoluteString).inserted
        }
    }

    /// Extracts the first `<img ... src="...">` URL from an HTML fragment.
    private func firstImageSource(inHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<img[^>]+src=[\"']([^\"']+)[\"']",
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[captured])
    }

    /// TEMP diagnostic: logs every pasteboard type and the contents of the
    /// text-ish ones, so we can see exactly what Safari/Chrome hand a service.
    private func logPasteboardInventory(_ pboard: NSPasteboard) {
        let types = (pboard.types ?? []).map(\.rawValue)
        Self.logger.notice("Services pasteboard types: \(types.joined(separator: ", "), privacy: .public)")
        for type in [NSPasteboard.PasteboardType.string, .html, .URL, .fileURL] {
            if let value = pboard.string(forType: type) {
                Self.logger.notice("  [\(type.rawValue, privacy: .public)] = \(value.prefix(400), privacy: .public)")
            }
        }
    }

    private func bestImageData(from pboard: NSPasteboard) -> (data: Data, ext: String)? {
        // Prefer the original GIF representation so animation survives.
        if let data = pboard.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")) {
            return (data, "gif")
        }
        if let data = pboard.data(forType: .png) { return (data, "png") }
        if let data = pboard.data(forType: .tiff) { return (data, "tiff") }
        return nil
    }

    private static func downloadMedia(from url: URL) async -> URL? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !data.isEmpty, let ext = mediaExtension(for: url, response: response) else { return nil }
            return writeTempFile(data: data, ext: ext)
        } catch {
            logger.warning("Service download failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func writeTempFile(data: Data, ext: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlidrService-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url)
            return url
        } catch {
            logger.warning("Failed to write temp import file: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Resolves a supported media file extension from the server's content type,
    /// falling back to the URL's own extension. Returns nil for non-media
    /// responses so plain web pages are ignored.
    private static func mediaExtension(for url: URL, response: URLResponse) -> String? {
        if let mime = response.mimeType?.lowercased(), let ext = extensionForMIME(mime) {
            return ext
        }
        let urlExt = url.pathExtension.lowercased()
        return FileTypeDetector.supportedExtensions.contains(urlExt) ? urlExt : nil
    }

    private static func extensionForMIME(_ mime: String) -> String? {
        switch mime {
        case "image/gif": return "gif"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "image/heic", "image/heif": return "heic"
        case "image/tiff": return "tiff"
        case "image/bmp": return "bmp"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "video/x-m4v": return "m4v"
        case "video/webm": return "webm"
        case "video/x-msvideo": return "avi"
        default: return nil
        }
    }
}
