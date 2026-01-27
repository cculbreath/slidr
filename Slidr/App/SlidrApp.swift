import SwiftUI
import SwiftData

@main
struct SlidrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let modelContainer: ModelContainer
    let mediaLibrary: MediaLibrary
    let thumbnailCache: ThumbnailCache
    let folderWatcher: FolderWatcher
    let playlistService: PlaylistService
    let hoverVideoPlayer: HoverVideoPlayer

    init() {
        // Initialize SwiftData container with versioned schema and migration plan
        let schema = Schema(versionedSchema: SlidrSchemaV3.self)
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
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Initialize services
        let thumbnailDir = slidrDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)

        thumbnailCache = ThumbnailCache(cacheDirectory: thumbnailDir)
        mediaLibrary = MediaLibrary(modelContainer: modelContainer, thumbnailCache: thumbnailCache)
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
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Slidr Help") {
                    NSApp.sendAction(#selector(NSApplication.showHelp(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            // Edit menu - replace system Select All with grid selection
            CommandGroup(replacing: .textEditing) {
                Button("Select All") {
                    NotificationCenter.default.post(name: .selectAll, object: nil)
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Deselect All") {
                    NotificationCenter.default.post(name: .deselectAll, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }

            CommandGroup(after: .textEditing) {
                Divider()

                Button("Find...") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // File menu
            CommandGroup(after: .newItem) {
                Button("Import Files...") {
                    NotificationCenter.default.post(name: .importFiles, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Divider()

                Button("New Playlist") {
                    NotificationCenter.default.post(name: .newPlaylist, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Smart Playlist") {
                    NotificationCenter.default.post(name: .newSmartPlaylist, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Delete Selected") {
                    NotificationCenter.default.post(name: .deleteSelected, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
            }

            // View menu
            CommandGroup(after: .toolbar) {
                Button("Larger Thumbnails") {
                    NotificationCenter.default.post(name: .increaseThumbnailSize, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Smaller Thumbnails") {
                    NotificationCenter.default.post(name: .decreaseThumbnailSize, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Thumbnail Size") {
                    NotificationCenter.default.post(name: .resetThumbnailSize, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Enter Fullscreen Slideshow") {
                    NotificationCenter.default.post(name: .startSlideshow, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Reveal in Finder") {
                    NotificationCenter.default.post(name: .revealInFinder, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
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
    }
}
