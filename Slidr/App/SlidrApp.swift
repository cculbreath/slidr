import SwiftUI
import SwiftData

@main
struct SlidrApp: App {
    let modelContainer: ModelContainer
    let mediaLibrary: MediaLibrary
    let thumbnailCache: ThumbnailCache

    init() {
        // Initialize SwiftData container
        let schema = Schema([MediaItem.self, Playlist.self])
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yoinkrDir = appSupport.appendingPathComponent("Slidr", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: yoinkrDir, withIntermediateDirectories: true)

        let storeURL = yoinkrDir.appendingPathComponent("Slidr.store")
        let config = ModelConfiguration("Slidr", schema: schema, url: storeURL)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Initialize services
        let thumbnailDir = yoinkrDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)

        thumbnailCache = ThumbnailCache(cacheDirectory: thumbnailDir)
        mediaLibrary = MediaLibrary(modelContainer: modelContainer, thumbnailCache: thumbnailCache)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(mediaLibrary)
        }
        .modelContainer(modelContainer)

        Settings {
            Text("Settings coming in Phase 4")
                .padding()
        }
    }
}
