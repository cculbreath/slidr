import OSLog

extension Logger {
    private static let subsystem = "com.physicscloud.slidr"

    nonisolated static let library = Logger(subsystem: subsystem, category: "Library")
    nonisolated static let importing = Logger(subsystem: subsystem, category: "Import")
    nonisolated static let playback = Logger(subsystem: subsystem, category: "Playback")
    nonisolated static let thumbnails = Logger(subsystem: subsystem, category: "Thumbnails")
    nonisolated static let playlists = Logger(subsystem: subsystem, category: "Playlist")
    nonisolated static let scrubber = Logger(subsystem: subsystem, category: "Scrubber")
    nonisolated static let folderWatcher = Logger(subsystem: subsystem, category: "FolderWatcher")
    nonisolated static let hoverPlayer = Logger(subsystem: subsystem, category: "HoverPlayer")
    nonisolated static let transcripts = Logger(subsystem: subsystem, category: "Transcripts")
    nonisolated static let vault = Logger(subsystem: subsystem, category: "Vault")
}
