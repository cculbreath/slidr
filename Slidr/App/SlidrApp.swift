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
        // Initialize SwiftData container with versioned schema and migration plan
        let schema = Schema(versionedSchema: SlidrSchemaV8.self)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let slidrDir = appSupport.appendingPathComponent("Slidr", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: slidrDir, withIntermediateDirectories: true)

        let storeURL = slidrDir.appendingPathComponent("Slidr.store")
        let config = ModelConfiguration("Slidr", schema: schema, url: storeURL)

        do {
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: SlidrMigrationPlan.self,
                configurations: config
            )
        } catch {
            // NEVER delete the data store automatically - user data is precious
            // Instead, log the error and present it to the user
            Logger.library.error("ModelContainer creation failed: \(error.localizedDescription)")
            Logger.library.error("Store URL: \(storeURL.path)")

            // Show an alert to the user about the database issue
            let alert = NSAlert()
            alert.messageText = "Database Migration Failed"
            alert.informativeText = """
                Slidr could not open your media library due to a database compatibility issue.

                Error: \(error.localizedDescription)

                Your data has NOT been deleted. You can:
                • Restore from a backup
                • Contact support for help with migration
                • Move the database file to reset (at your own risk)

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

            fatalError("Cannot continue without a valid database. Please resolve the migration issue and relaunch.")
        }

        // Ensure AppSettings exists
        let context = modelContainer.mainContext
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        if (try? context.fetchCount(settingsDescriptor)) == 0 {
            context.insert(AppSettings())
            try? context.save()
            Logger.library.info("Created default AppSettings")
        }

        // Initialize services
        let thumbnailDir = slidrDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)

        thumbnailCache = ThumbnailCache(cacheDirectory: thumbnailDir)

        let transcriptDir = slidrDir.appendingPathComponent("Transcripts", isDirectory: true)
        try? FileManager.default.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
        transcriptStore = TranscriptStore(transcriptDirectory: transcriptDir)

        mediaLibrary = MediaLibrary(modelContainer: modelContainer, thumbnailCache: thumbnailCache, transcriptStore: transcriptStore)

        // Configure external drive from settings
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            mediaLibrary.configureExternalDrive(path: settings.externalDrivePath)
        }

        folderWatcher = FolderWatcher()
        playlistService = PlaylistService(modelContainer: modelContainer, mediaLibrary: mediaLibrary, folderWatcher: folderWatcher)
        hoverVideoPlayer = HoverVideoPlayer()
    }

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
        // .windowResizability(.contentSize)
    }
}
