import SwiftUI
import SwiftData

@main
struct YoinkrApp: App {
    let modelContainer: ModelContainer
    let mediaLibrary: MediaLibrary
    let thumbnailCache: ThumbnailCache

    init() {
        // Initialize SwiftData container
        let schema = Schema([MediaItem.self, Playlist.self])
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yoinkrDir = appSupport.appendingPathComponent("Yoinkr", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: yoinkrDir, withIntermediateDirectories: true)

        let storeURL = yoinkrDir.appendingPathComponent("Yoinkr.store")
        let config = ModelConfiguration("Yoinkr", schema: schema, url: storeURL)

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
                .environment(thumbnailCache)
        }
        .modelContainer(modelContainer)

        Settings {
            Text("Settings coming in Phase 4")
                .padding()
        }
    }
}
