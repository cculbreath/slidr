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
    let folderWatcher: FolderWatcher
    let playlistService: PlaylistService
    let hoverVideoPlayer: HoverVideoPlayer

    init() {
        // Initialize SwiftData container with versioned schema and migration plan
        let schema = Schema(versionedSchema: SlidrSchemaV5.self)
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
        mediaLibrary = MediaLibrary(modelContainer: modelContainer, thumbnailCache: thumbnailCache)

        // Configure external drive from settings
        if let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
            mediaLibrary.configureExternalDrive(path: settings.externalDrivePath)
        }

        folderWatcher = FolderWatcher()
        playlistService = PlaylistService(modelContainer: modelContainer, mediaLibrary: mediaLibrary, folderWatcher: folderWatcher)
        hoverVideoPlayer = HoverVideoPlayer()
    }

    @FocusedValue(\.importDestination) var importDestination
    @FocusedValue(\.gridShowFilenames) var gridShowFilenames
    @FocusedValue(\.gridShowCaptions) var gridShowCaptions
    @FocusedValue(\.animateGIFs) var animateGIFs

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(mediaLibrary)
                .environment(playlistService)
                .environment(hoverVideoPlayer)
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Slidr Help") {
                    NSApp.sendAction(#selector(NSApplication.showHelp(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }

            // Replace pasteboard group to remove system Select All and add our own
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Button("Delete") {
                    NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: nil)
                }

                Divider()

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

                Menu("Import Destination") {
                    if let importDestination {
                        Picker(selection: importDestination) {
                            Text("Local Library").tag(StorageLocation.local)
                            Text("External Library").tag(StorageLocation.external)
                            Text("Reference in Place").tag(StorageLocation.referenced)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.inline)
                    }
                }

                Button("Locate External Library...") {
                    NotificationCenter.default.post(name: .locateExternalLibrary, object: nil)
                }

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

                if let gridShowFilenames {
                    Toggle("Show Grid Filenames", isOn: gridShowFilenames)
                }

                if let gridShowCaptions {
                    Toggle("Show Grid Captions", isOn: gridShowCaptions)
                }

                if let animateGIFs {
                    Toggle("Animate GIFs in Grid", isOn: animateGIFs)
                }

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
