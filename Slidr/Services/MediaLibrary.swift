import Foundation
import SwiftData
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.physicscloud.slidr", category: "Library")

@MainActor
@Observable
final class MediaLibrary {
    // MARK: - Published State
    private(set) var isLoading = false
    private(set) var itemCount = 0
    private(set) var lastError: Error?

    // MARK: - Dependencies
    let modelContainer: ModelContainer
    let thumbnailCache: ThumbnailCache
    private let fileManager = FileManager.default

    // MARK: - Paths
    let libraryRoot: URL

    // MARK: - Initialization
    init(modelContainer: ModelContainer, thumbnailCache: ThumbnailCache) {
        self.modelContainer = modelContainer
        self.thumbnailCache = thumbnailCache

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yoinkrDir = appSupport.appendingPathComponent("Slidr", isDirectory: true)
        self.libraryRoot = yoinkrDir.appendingPathComponent("Library", isDirectory: true)

        // Ensure directories exist
        try? fileManager.createDirectory(at: libraryRoot.appendingPathComponent("Local"), withIntermediateDirectories: true)

        updateItemCount()
    }

    // MARK: - Queries

    var allItems: [MediaItem] {
        let descriptor = FetchDescriptor<MediaItem>(
            sortBy: [SortDescriptor(\.importDate, order: .reverse)]
        )
        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    func items(matching predicate: Predicate<MediaItem>? = nil, sortedBy sortOrder: SortOrder = .dateImported, ascending: Bool = false) -> [MediaItem] {
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)

        switch sortOrder {
        case .name:
            descriptor.sortBy = [SortDescriptor(\.originalFilename, order: ascending ? .forward : .reverse)]
        case .dateModified:
            descriptor.sortBy = [SortDescriptor(\.fileModifiedDate, order: ascending ? .forward : .reverse)]
        case .dateImported:
            descriptor.sortBy = [SortDescriptor(\.importDate, order: ascending ? .forward : .reverse)]
        case .fileSize:
            descriptor.sortBy = [SortDescriptor(\.fileSize, order: ascending ? .forward : .reverse)]
        case .random:
            // Fetch all, then shuffle
            let items = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
            return items.shuffled()
        }

        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    // MARK: - Import

    func importFiles(urls: [URL]) async throws -> ImportResult {
        isLoading = true
        defer {
            isLoading = false
            updateItemCount()
        }

        let importer = MediaImporter(libraryRoot: libraryRoot, modelContext: modelContainer.mainContext)
        let result = try await importer.importFiles(urls: urls)

        logger.info("Import complete: \(result.summary)")
        return result
    }

    // MARK: - Delete

    func delete(_ item: MediaItem) {
        // Delete file
        let fileURL = libraryRoot.appendingPathComponent(item.relativePath)
        try? fileManager.removeItem(at: fileURL)

        // Delete thumbnails
        Task {
            await thumbnailCache.removeThumbnails(forHash: item.contentHash)
        }

        // Delete from database
        modelContainer.mainContext.delete(item)
        try? modelContainer.mainContext.save()

        updateItemCount()
        logger.info("Deleted: \(item.originalFilename)")
        NotificationCenter.default.post(name: .mediaItemsDeleted, object: nil)
    }

    func delete(_ items: [MediaItem]) {
        for item in items {
            // Delete file
            let fileURL = libraryRoot.appendingPathComponent(item.relativePath)
            try? fileManager.removeItem(at: fileURL)

            // Delete thumbnails
            Task {
                await thumbnailCache.removeThumbnails(forHash: item.contentHash)
            }

            // Delete from database
            modelContainer.mainContext.delete(item)
        }
        try? modelContainer.mainContext.save()
        updateItemCount()
        logger.info("Deleted \(items.count) items")
        NotificationCenter.default.post(name: .mediaItemsDeleted, object: nil)
    }

    // MARK: - Thumbnail Access

    func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> NSImage {
        try await thumbnailCache.thumbnail(for: item, size: size, libraryRoot: libraryRoot)
    }

    func videoScrubThumbnails(for item: MediaItem, count: Int, size: ThumbnailSize) async throws -> [NSImage] {
        try await thumbnailCache.videoScrubThumbnails(for: item, count: count, size: size, libraryRoot: libraryRoot)
    }

    // MARK: - Helpers

    private func updateItemCount() {
        let descriptor = FetchDescriptor<MediaItem>()
        itemCount = (try? modelContainer.mainContext.fetchCount(descriptor)) ?? 0
    }

    func absoluteURL(for item: MediaItem) -> URL {
        libraryRoot.appendingPathComponent(item.relativePath)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let mediaItemsDeleted = Notification.Name("com.physicscloud.slidr.mediaItemsDeleted")
}
