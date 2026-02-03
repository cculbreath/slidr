import SwiftUI
import SwiftData
import OSLog
import AppKit

@main
struct SlidrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var launcher = AppLauncher()

    var body: some Scene {
        WindowGroup {
            ZStack {
                // ContentView is always present once the container exists.
                // This keeps the NSView hierarchy (and AppKit toolbar) stable
                // across vault lock/unlock transitions.
                if let c = launcher.container {
                    ContentView()
                        .modelContainer(c.modelContainer)
                        .environment(c.mediaLibrary)
                        .environment(c.playlistService)
                        .environment(c.hoverVideoPlayer)
                        .environment(c.aiCoordinator)
                        .environment(\.transcriptStore, c.transcriptStore)
                        .preferredColorScheme(.dark)
                }

                // Lock/init overlays sit on top and block interaction until ready
                if launcher.phase == .initializing {
                    ProgressView("Initializing Slidr...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .preferredColorScheme(.dark)
                }

                if launcher.phase == .locked {
                    VaultLockScreenView { password, useKeychain in
                        try await launcher.handleUnlock(password: password, useKeychain: useKeychain)
                    }
                }
            }
        }
        .windowToolbarStyle(.unified)
        .commands {
            SlidrCommands()
        }

        Settings {
            if let c = launcher.container {
                SettingsView(thumbnailCache: c.thumbnailCache)
                    .modelContainer(c.modelContainer)
                    .environment(c.mediaLibrary)
            }
        }

        Window("About Slidr", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        WindowGroup("Edit Playlist", for: UUID.self) { $playlistID in
            if let c = launcher.container,
               let playlistID,
               let playlist = c.playlistService.playlist(withID: playlistID) {
                PlaylistEditorView(playlist: playlist)
                    .modelContainer(c.modelContainer)
                    .environment(c.playlistService)
            }
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - AppContainer

/// Holds all services created after vault unlock (or immediately in non-vault mode).
struct AppContainer {
    let modelContainer: ModelContainer
    let mediaLibrary: MediaLibrary
    let thumbnailCache: ThumbnailCache
    let transcriptStore: TranscriptStore
    let folderWatcher: FolderWatcher
    let playlistService: PlaylistService
    let hoverVideoPlayer: HoverVideoPlayer
    let aiCoordinator: AIProcessingCoordinator
}

// MARK: - AppLauncher

/// Manages two-phase app launch: vault check → lock screen or direct launch.
@MainActor
@Observable
final class AppLauncher {
    enum Phase {
        case initializing
        case locked
        case ready
    }

    private(set) var phase: Phase = .initializing
    private(set) var container: AppContainer?
    let slidrDirectory: URL
    private var vaultService: VaultService?
    var lifecycleManager: VaultLifecycleManager?

    init() {
        slidrDirectory = Self.ensureSlidrDirectory()

        // Check vault mode synchronously by reading the manifest file directly.
        // VaultService is an actor, so we avoid async calls in init.
        let vaultEnabled = Self.isVaultEnabled(slidrDir: slidrDirectory)

        if vaultEnabled {
            phase = .locked
        } else {
            let pathProvider = StoragePathProvider(slidrDirectory: slidrDirectory)
            do {
                container = try Self.createAppContainer(
                    slidrDirectory: slidrDirectory,
                    pathProvider: pathProvider
                )
                phase = .ready
            } catch {
                Logger.library.error("Failed to initialize app: \(error.localizedDescription)")
                fatalError("Cannot continue without a valid database. Please resolve the issue and relaunch.")
            }
        }
    }

    // MARK: - Vault Unlock

    func handleUnlock(password: String, useKeychain: Bool) async throws {
        let service = try VaultService(slidrDirectory: slidrDirectory)
        let mountPoints = try await service.mountAllEnabled(password: password)

        // Resolve local vault mount
        let localVault = await service.localVault()
        let localMount = localVault.flatMap { mountPoints[$0.id] }

        // Collect external vault mounts
        var externalMounts: [UUID: URL] = [:]
        for vault in await service.externalVaults() {
            if let mount = mountPoints[vault.id] {
                externalMounts[vault.id] = mount
            }
        }

        let pathProvider = StoragePathProvider(
            slidrDirectory: slidrDirectory,
            vaultMode: true,
            localVaultMount: localMount,
            externalVaultMounts: externalMounts
        )

        container = try Self.createAppContainer(
            slidrDirectory: slidrDirectory,
            pathProvider: pathProvider
        )

        if useKeychain {
            try? KeychainHelper.savePassword(password)
        }

        vaultService = service

        // Start auto-lock monitoring
        let manifest = await service.manifest
        let manager = VaultLifecycleManager(vaultService: service) { [weak self] in
            await self?.lock()
        }
        manager.startMonitoring(
            autoLockOnSleep: manifest.autoLockOnSleep,
            autoLockOnScreensaver: manifest.autoLockOnScreensaver,
            lockTimeoutMinutes: manifest.lockTimeoutMinutes
        )
        lifecycleManager = manager

        phase = .ready
    }

    // MARK: - Lock

    func lock() async {
        if let service = vaultService {
            await service.unmountAllVaults()
        }
        lifecycleManager?.stopMonitoring()
        lifecycleManager = nil
        container = nil
        phase = .locked
    }

    // MARK: - Vault Mode Check

    private static func isVaultEnabled(slidrDir: URL) -> Bool {
        let manifestURL = slidrDir.appendingPathComponent(VaultManifest.filename)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(VaultManifest.self, from: data) else {
            return false
        }
        return !manifest.vaults.isEmpty
    }

    // MARK: - App Container Creation

    private static func createAppContainer(
        slidrDirectory: URL,
        pathProvider: StoragePathProvider
    ) throws -> AppContainer {
        let modelContainer = try createModelContainer(storeURL: pathProvider.databaseURL)
        ensureAppSettingsExists(in: modelContainer)

        let thumbnailCache = createThumbnailCache(at: pathProvider.thumbnailCacheURL)
        let transcriptStore = createTranscriptStore(at: pathProvider.transcriptStoreURL)

        let mediaLibrary = MediaLibrary(
            modelContainer: modelContainer,
            thumbnailCache: thumbnailCache,
            transcriptStore: transcriptStore,
            libraryRoot: pathProvider.libraryRootURL
        )

        // Configure external drive root.
        // In vault mode: point at the first external vault mount so media resolves from the vault.
        // In non-vault mode: read from AppSettings as usual.
        if pathProvider.vaultMode, let firstExtMount = pathProvider.allExternalMounts.values.first {
            mediaLibrary.configureExternalDrive(path: firstExtMount.path)
        } else if !pathProvider.vaultMode {
            configureExternalDrive(library: mediaLibrary, container: modelContainer)
        }

        let folderWatcher = FolderWatcher()
        let playlistService = PlaylistService(
            modelContainer: modelContainer,
            mediaLibrary: mediaLibrary,
            folderWatcher: folderWatcher
        )
        let hoverVideoPlayer = HoverVideoPlayer()
        let aiCoordinator = AIProcessingCoordinator()

        return AppContainer(
            modelContainer: modelContainer,
            mediaLibrary: mediaLibrary,
            thumbnailCache: thumbnailCache,
            transcriptStore: transcriptStore,
            folderWatcher: folderWatcher,
            playlistService: playlistService,
            hoverVideoPlayer: hoverVideoPlayer,
            aiCoordinator: aiCoordinator
        )
    }

    // MARK: - Setup Helpers

    private static func ensureSlidrDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let slidrDir = appSupport.appendingPathComponent("Slidr", isDirectory: true)
        try? FileManager.default.createDirectory(at: slidrDir, withIntermediateDirectories: true)
        return slidrDir
    }

    private static func createModelContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SlidrSchemaV15.self)
        let config = ModelConfiguration("Slidr", schema: schema, url: storeURL)

        do {
            return try ModelContainer(
                for: schema,
                configurations: config
            )
        } catch {
            Logger.library.error("ModelContainer creation failed: \(error.localizedDescription)")
            Logger.library.error("Store URL: \(storeURL.path)")
            presentDatabaseError(storeURL: storeURL, error: error)
            throw error
        }
    }

    private static func presentDatabaseError(storeURL: URL, error: Error) {
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
            NSWorkspace.shared.selectFile(storeURL.path, inFileViewerRootedAtPath: storeURL.deletingLastPathComponent().path)
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

    private static func createThumbnailCache(at cacheURL: URL) -> ThumbnailCache {
        try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        return ThumbnailCache(cacheDirectory: cacheURL)
    }

    private static func createTranscriptStore(at transcriptURL: URL) -> TranscriptStore {
        try? FileManager.default.createDirectory(at: transcriptURL, withIntermediateDirectories: true)
        return TranscriptStore(transcriptDirectory: transcriptURL)
    }

    private static func configureExternalDrive(library: MediaLibrary, container: ModelContainer) {
        if let settings = try? container.mainContext.fetch(FetchDescriptor<AppSettings>()).first {
            library.configureExternalDrive(path: settings.externalDrivePath)
        }
    }

}
