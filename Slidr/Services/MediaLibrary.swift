import Foundation
import SwiftData
import AppKit
import OSLog

@MainActor
@Observable
final class MediaLibrary {
    // MARK: - Published State
    private(set) var isLoading = false
    private(set) var itemCount = 0
    private(set) var lastError: LibraryError?
    private(set) var libraryVersion: Int = 0
    private(set) var lastImportDate: Date?

    // MARK: - Dependencies
    let modelContainer: ModelContainer
    let thumbnailCache: ThumbnailCache
    private let fileManager = FileManager.default

    // MARK: - Paths
    private(set) var libraryRoot: URL
    var externalLibraryRoot: URL?

    // MARK: - Initialization
    init(modelContainer: ModelContainer, thumbnailCache: ThumbnailCache) {
        self.modelContainer = modelContainer
        self.thumbnailCache = thumbnailCache

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let slidrDir = appSupport.appendingPathComponent("Slidr", isDirectory: true)
        self.libraryRoot = slidrDir.appendingPathComponent("Library", isDirectory: true)

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
        case .duration:
            descriptor.sortBy = [SortDescriptor(\.duration, order: ascending ? .forward : .reverse)]
        case .random:
            // Fetch all, then shuffle
            let items = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
            return items.shuffled()
        }

        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    // MARK: - Item Management

    func add(_ item: MediaItem) {
        modelContainer.mainContext.insert(item)
        try? modelContainer.mainContext.save()
        updateItemCount()
    }

    func items(inFolder folder: String, includeSubfolders: Bool) -> [MediaItem] {
        allItems.filter { item in
            if includeSubfolders {
                return item.relativePath.hasPrefix(folder)
            } else {
                let itemFolder = (item.relativePath as NSString).deletingLastPathComponent
                return itemFolder == folder
            }
        }
    }

    // MARK: - Import

    func importFiles(urls: [URL], options: ImportOptions = .default) async throws -> ImportResult {
        isLoading = true
        defer {
            isLoading = false
            updateItemCount()
        }

        let importer = MediaImporter(libraryRoot: libraryRoot, modelContext: modelContainer.mainContext, options: options)
        let result = try await importer.importFiles(urls: urls)

        if !result.imported.isEmpty {
            lastImportDate = Date()
        }

        Logger.library.info("Import complete: \(result.summary)")
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
        Logger.library.info("Deleted: \(item.originalFilename)")
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
        Logger.library.info("Deleted \(items.count) items")
        NotificationCenter.default.post(name: .mediaItemsDeleted, object: nil)
    }

    // MARK: - Thumbnail Access

    func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> NSImage {
        try await thumbnailCache.thumbnail(for: item, size: size, libraryRoot: libraryRoot)
    }

    func videoScrubThumbnails(for item: MediaItem, count: Int, size: ThumbnailSize) async throws -> [NSImage] {
        try await thumbnailCache.videoScrubThumbnails(for: item, count: count, size: size, libraryRoot: libraryRoot)
    }

    // MARK: - Library Path Management

    func setLibraryRoot(_ url: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let localDir = url.appendingPathComponent("Local", isDirectory: true)
        try fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)

        libraryRoot = url
        Logger.library.info("Library root changed to: \(url.path)")
    }

    func migrateLibrary(to newPath: URL, progress: ((Double) -> Void)? = nil) async throws {
        let fileManager = FileManager.default
        let oldPath = libraryRoot

        guard oldPath != newPath else { return }

        let oldLocalDir = oldPath.appendingPathComponent("Local")
        guard let files = try? fileManager.contentsOfDirectory(
            at: oldLocalDir,
            includingPropertiesForKeys: nil
        ) else { return }

        let totalFiles = files.count
        var processed = 0

        let newLocalDir = newPath.appendingPathComponent("Local", isDirectory: true)
        try fileManager.createDirectory(at: newLocalDir, withIntermediateDirectories: true)

        for file in files {
            let destination = newLocalDir.appendingPathComponent(file.lastPathComponent)
            try fileManager.copyItem(at: file, to: destination)
            processed += 1
            progress?(Double(processed) / Double(totalFiles))
        }

        libraryRoot = newPath
        Logger.library.info("Library migrated from \(oldPath.path) to \(newPath.path)")
    }

    // MARK: - Smart Albums

    func lastImportItems(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        guard let importDate = lastImportDate else { return [] }
        let threshold = importDate.addingTimeInterval(-2)
        return items(sortedBy: sortOrder, ascending: ascending)
            .filter { $0.importDate >= threshold }
    }

    func importedTodayItems(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return items(sortedBy: sortOrder, ascending: ascending)
            .filter { $0.importDate >= startOfDay }
    }

    // MARK: - Helpers

    private func updateItemCount() {
        let descriptor = FetchDescriptor<MediaItem>()
        itemCount = (try? modelContainer.mainContext.fetchCount(descriptor)) ?? 0
        libraryVersion += 1
    }

    func absoluteURL(for item: MediaItem) -> URL {
        if item.storageLocation == .referenced {
            return URL(fileURLWithPath: item.relativePath)
        }
        return libraryRoot.appendingPathComponent(item.relativePath)
    }

    // MARK: - External Drive Support

    func isAccessible(_ item: MediaItem) -> Bool {
        let url = absoluteURL(for: item)
        return fileManager.fileExists(atPath: url.path)
    }

    func inaccessibleItems() -> [MediaItem] {
        allItems.filter { !isAccessible($0) }
    }

    func items(in location: StorageLocation) -> [MediaItem] {
        allItems.filter { $0.storageLocation == location }
    }

    // MARK: - Verification

    func verifyLibraryIntegrity() async -> VerificationResult {
        let startTime = Date()
        let items = allItems
        let totalItems = items.count
        var verifiedCount = 0
        var missingCount = 0

        for item in items {
            let url = absoluteURL(for: item)
            if fileManager.fileExists(atPath: url.path) {
                if item.status == .missing {
                    item.status = .available
                }
                item.lastVerifiedDate = Date()
                verifiedCount += 1
            } else {
                item.status = .missing
                item.lastVerifiedDate = Date()
                missingCount += 1
            }
        }

        try? modelContainer.mainContext.save()

        let orphanedCount = await countOrphanedThumbnails()

        let duration = Date().timeIntervalSince(startTime)
        Logger.library.info("Library verification complete: \(verifiedCount)/\(totalItems) verified, \(missingCount) missing, \(orphanedCount) orphaned thumbnails")

        return VerificationResult(
            totalItems: totalItems,
            verifiedItems: verifiedCount,
            missingItems: missingCount,
            orphanedThumbnails: orphanedCount,
            duration: duration
        )
    }

    func item(withHash hash: String) -> MediaItem? {
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    func cleanOrphanedThumbnails() async {
        let existingHashes = Set(allItems.map(\.contentHash))
        await thumbnailCache.pruneOrphanedThumbnails(existingHashes: existingHashes)
        Logger.library.info("Orphaned thumbnail cleanup complete")
    }

    func removeOrphanedItems() {
        let orphaned = allItems.filter { $0.status == .missing }
        guard !orphaned.isEmpty else { return }

        for item in orphaned {
            Task {
                await thumbnailCache.removeThumbnails(forHash: item.contentHash)
            }
            modelContainer.mainContext.delete(item)
        }

        try? modelContainer.mainContext.save()
        updateItemCount()
        Logger.library.info("Removed \(orphaned.count) orphaned items with .missing status")

        if !orphaned.isEmpty {
            NotificationCenter.default.post(name: .mediaItemsDeleted, object: nil)
        }
    }

    // MARK: - Private Verification Helpers

    private func countOrphanedThumbnails() async -> Int {
        let existingHashes = Set(allItems.map(\.contentHash))
        let diskCount = await thumbnailCache.diskCacheCount()
        // Each item can have up to ThumbnailSize.allCases.count cached thumbnails
        // An orphaned thumbnail is one whose hash doesn't match any existing item
        // We approximate by checking the disk cache - exact count comes from pruning
        let expectedMaxThumbnails = existingHashes.count * ThumbnailSize.allCases.count
        return max(0, diskCount - expectedMaxThumbnails)
    }

    // MARK: - Copy to Library

    func copyToLibrary(_ item: MediaItem) async throws {
        guard item.storageLocation == .referenced else { return }

        let sourceURL = URL(fileURLWithPath: item.relativePath)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw LibraryError.sourceFileNotFound
        }

        let year = Calendar.current.component(.year, from: Date())
        let yearDir = libraryRoot.appendingPathComponent("Local/\(year)", isDirectory: true)
        try fileManager.createDirectory(at: yearDir, withIntermediateDirectories: true)

        let destinationFilename = "\(UUID().uuidString).\(sourceURL.pathExtension)"
        let destinationURL = yearDir.appendingPathComponent(destinationFilename)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        // Update the item to point to the new location
        item.relativePath = "Local/\(year)/\(destinationFilename)"
        item.storageLocation = .local
        try? modelContainer.mainContext.save()

        Logger.library.info("Copied to library: \(item.originalFilename)")
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let mediaItemsDeleted = Notification.Name("com.physicscloud.slidr.mediaItemsDeleted")
}
