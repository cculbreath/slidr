import Foundation
import OSLog

/// Watches filesystem directories for changes using FSEvents.
/// Thread-safe actor that manages multiple folder watch streams.
actor FolderWatcher {
    typealias EventHandler = @Sendable (URL, FSEventType) -> Void

    private static let logger = Logger(subsystem: "com.physicscloud.slidr", category: "FolderWatcher")

    private struct WatchEntry {
        let streamRef: FSEventStreamRef
        let handler: EventHandler
    }

    private var watchers: [String: WatchEntry] = [:]
    private let eventQueue = DispatchQueue(label: "com.physicscloud.slidr.fswatcher", qos: .utility)

    // MARK: - Public API

    /// Begin watching a folder for filesystem events.
    /// - Parameters:
    ///   - url: The folder URL to watch.
    ///   - includeSubfolders: Whether to recursively watch subdirectories.
    ///   - handler: Callback invoked on each detected event.
    func watch(url: URL, includeSubfolders: Bool, handler: @escaping EventHandler) {
        let path = url.path
        // Stop any existing watcher for this path
        stopWatchingSync(path: path)

        let pathsToWatch = [path] as CFArray
        let latency: CFTimeInterval = 1.0

        // Context to pass handler into the C callback
        let handlerBox = Unmanaged.passRetained(HandlerBox(handler: handler))
        var context = FSEventStreamContext(
            version: 0,
            info: handlerBox.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        var flags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagFileEvents)
            | UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagNoDefer)

        if !includeSubfolders {
            flags |= UInt32(kFSEventStreamCreateFlagWatchRoot)
        }

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let box = Unmanaged<HandlerBox>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            let flagsBuf = UnsafeBufferPointer(start: eventFlags, count: numEvents)

            for i in 0..<numEvents {
                let eventPath = paths[i]
                let eventFlag = flagsBuf[i]
                let eventURL = URL(fileURLWithPath: eventPath)
                let eventType = FolderWatcher.eventType(from: eventFlag)
                box.handler(eventURL, eventType)
            }
        }

        guard let streamRef = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            Self.logger.error("Failed to create FSEventStream for \(path)")
            handlerBox.release()
            return
        }

        FSEventStreamSetDispatchQueue(streamRef, eventQueue)
        FSEventStreamStart(streamRef)

        watchers[path] = WatchEntry(streamRef: streamRef, handler: handler)
        Self.logger.info("Started watching: \(path)")
    }

    /// Stop watching a specific folder.
    func stopWatching(url: URL) {
        stopWatchingSync(path: url.path)
    }

    /// Stop all active folder watchers.
    func stopAll() {
        for path in watchers.keys {
            stopWatchingSync(path: path)
        }
    }

    // MARK: - Private

    private func stopWatchingSync(path: String) {
        guard let entry = watchers.removeValue(forKey: path) else { return }
        FSEventStreamStop(entry.streamRef)
        FSEventStreamInvalidate(entry.streamRef)
        FSEventStreamRelease(entry.streamRef)
        Self.logger.info("Stopped watching: \(path)")
    }

    /// Map FSEvent flags to our FSEventType enum.
    nonisolated static func eventType(from flags: FSEventStreamEventFlags) -> FSEventType {
        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
            return .created
        } else if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            return .deleted
        } else if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
            return .renamed
        } else {
            return .modified
        }
    }
}

// MARK: - Handler Box (reference type for C callback context)

private final class HandlerBox: @unchecked Sendable {
    let handler: FolderWatcher.EventHandler

    nonisolated init(handler: @escaping FolderWatcher.EventHandler) {
        self.handler = handler
    }
}
