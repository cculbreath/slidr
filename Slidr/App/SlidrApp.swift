import SwiftUI
import SwiftData
import OSLog
import AppKit

@main
struct SlidrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let modelContainer: ModelContainer
    let mediaLibrary: MediaLibrary
    let thumbnailCache: ThumbnailCache
    let transcriptStore: TranscriptStore
    let folderWatcher: FolderWatcher
    let playlistService: PlaylistService
    let hoverVideoPlayer: HoverVideoPlayer

    init() {
        let slidrDir = Self.ensureSlidrDirectory()
        modelContainer = Self.createModelContainer(slidrDir: slidrDir)
        Self.ensureAppSettingsExists(in: modelContainer)

        thumbnailCache = Self.createThumbnailCache(slidrDir: slidrDir)
        transcriptStore = Self.createTranscriptStore(slidrDir: slidrDir)

        mediaLibrary = MediaLibrary(
            modelContainer: modelContainer,
            thumbnailCache: thumbnailCache,
            transcriptStore: transcriptStore
        )

        Self.configureExternalDrive(library: mediaLibrary, container: modelContainer)

        TagCleanup.runIfNeeded(
            container: modelContainer,
            allowlistPath: NSString("~/Downloads/modnewtaglist.csv").expandingTildeInPath,
            replacementsPath: NSString("~/devlocal/video-tags/newReplacements.txt").expandingTildeInPath
        )

        folderWatcher = FolderWatcher()
        playlistService = PlaylistService(modelContainer: modelContainer, mediaLibrary: mediaLibrary, folderWatcher: folderWatcher)
        hoverVideoPlayer = HoverVideoPlayer()
    }

    // MARK: - Setup Helpers

    private static func ensureSlidrDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let slidrDir = appSupport.appendingPathComponent("Slidr", isDirectory: true)
        try? FileManager.default.createDirectory(at: slidrDir, withIntermediateDirectories: true)
        return slidrDir
    }

    private static func createModelContainer(slidrDir: URL) -> ModelContainer {
        let schema = Schema(versionedSchema: SlidrSchemaV11.self)
        let storeURL = slidrDir.appendingPathComponent("Slidr.store")
        let config = ModelConfiguration("Slidr", schema: schema, url: storeURL)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SlidrMigrationPlan.self,
                configurations: config
            )
        } catch {
            Logger.library.error("ModelContainer creation failed: \(error.localizedDescription)")
            Logger.library.error("Store URL: \(storeURL.path)")
            presentDatabaseError(storeURL: storeURL, slidrDir: slidrDir, error: error)
            fatalError("Cannot continue without a valid database. Please resolve the migration issue and relaunch.")
        }
    }

    private static func presentDatabaseError(storeURL: URL, slidrDir: URL, error: Error) {
        let alert = NSAlert()
        alert.messageText = "Database Migration Failed"
        alert.informativeText = """
            Slidr could not open your media library due to a database compatibility issue.

            Error: \(error.localizedDescription)

            Your data has NOT been deleted. You can:
            \u{2022} Restore from a backup
            \u{2022} Contact support for help with migration
            \u{2022} Move the database file to reset (at your own risk)

            Database location:
            \(storeURL.path)
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.selectFile(storeURL.path, inFileViewerRootedAtPath: slidrDir.path)
        }
    }

    private static func ensureAppSettingsExists(in container: ModelContainer) {
        let context = container.mainContext
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        if (try? context.fetchCount(settingsDescriptor)) == 0 {
            context.insert(AppSettings())
            try? context.save()
            Logger.library.info("Created default AppSettings")
        }
    }

    private static func createThumbnailCache(slidrDir: URL) -> ThumbnailCache {
        let thumbnailDir = slidrDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
        return ThumbnailCache(cacheDirectory: thumbnailDir)
    }

    private static func createTranscriptStore(slidrDir: URL) -> TranscriptStore {
        let transcriptDir = slidrDir.appendingPathComponent("Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
        return TranscriptStore(transcriptDirectory: transcriptDir)
    }

    private static func configureExternalDrive(library: MediaLibrary, container: ModelContainer) {
        if let settings = try? container.mainContext.fetch(FetchDescriptor<AppSettings>()).first {
            library.configureExternalDrive(path: settings.externalDrivePath)
        }
    }

    // MARK: - Scenes

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(mediaLibrary)
                .environment(playlistService)
                .environment(hoverVideoPlayer)
                .environment(\.transcriptStore, transcriptStore)
                .preferredColorScheme(.dark)
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SlidrCommands()
        }

        Settings {
            SettingsView(thumbnailCache: thumbnailCache)
                .environment(mediaLibrary)
        }
        .modelContainer(modelContainer)

        Window("About Slidr", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        WindowGroup("Edit Playlist", for: UUID.self) { $playlistID in
            if let playlistID, let playlist = playlistService.playlist(withID: playlistID) {
                PlaylistEditorView(playlist: playlist)
                    .environment(playlistService)
            }
        }
        .modelContainer(modelContainer)
        .windowResizability(.contentSize)
    }
}
