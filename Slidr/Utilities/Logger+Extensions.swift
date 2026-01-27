import OSLog

extension Logger {
    private static let subsystem = "com.physicscloud.slidr"

    static let library = Logger(subsystem: subsystem, category: "Library")
    static let importing = Logger(subsystem: subsystem, category: "Import")
    static let playback = Logger(subsystem: subsystem, category: "Playback")
    static let thumbnails = Logger(subsystem: subsystem, category: "Thumbnails")
    static let playlists = Logger(subsystem: subsystem, category: "Playlist")
    static let scrubber = Logger(subsystem: subsystem, category: "Scrubber")
    static let folderWatcher = Logger(subsystem: subsystem, category: "FolderWatcher")
    static let hoverPlayer = Logger(subsystem: subsystem, category: "HoverPlayer")
}
