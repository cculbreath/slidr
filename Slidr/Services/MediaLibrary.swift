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
    private(set) var isExternalDriveConnected = false
    private(set) var externalItemCount = 0

    // Import progress
    private(set) var importProgress: ImportProgress?
    private(set) var importCancelled = false

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

    /// All unique tags used across the library, sorted alphabetically
    var allTags: [String] {
        let tagSets = allItems.map { Set($0.tags) }
        let allTags = tagSets.reduce(into: Set<String>()) { $0.formUnion($1) }
        return allTags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// All unique sources used across the library, sorted alphabetically
    var allSources: [String] {
        let sources = allItems.compactMap { $0.source }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(Set(sources)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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

    func cancelImport() {
        importCancelled = true
        isLoading = false
        importProgress = nil
        Logger.library.info("Import cancelled by user")
    }

    func importFiles(urls: [URL], options: ImportOptions = .default) async throws -> ImportResult {
        isLoading = true
        importCancelled = false
        importProgress = ImportProgress(currentItem: 0, totalItems: urls.count, currentFilename: "", phase: .importing)
        defer {
            isLoading = false
            importProgress = nil
            updateItemCount()
            updateExternalItemCount()
        }

        let importer = MediaImporter(libraryRoot: libraryRoot, externalLibraryRoot: externalLibraryRoot, modelContext: modelContainer.mainContext, options: options)
        let result = try await importer.importFiles(urls: urls) { [weak self] progress in
            Task { @MainActor in
                guard self?.isLoading == true else { return }
                self?.importProgress = progress
            }
        }

        if !result.imported.isEmpty {
            lastImportDate = Date()

            // Generate scrub thumbnails for imported videos in the background
            let videoItems = result.imported.filter { $0.isVideo }
            if !videoItems.isEmpty {
                let descriptor = FetchDescriptor<AppSettings>()
                let count = (try? modelContainer.mainContext.fetch(descriptor).first?.scrubThumbnailCount) ?? 100
                generateScrubThumbnailsForVideos(videoItems, count: count)
            }
        }

        Logger.library.info("Import complete: \(result.summary)")
        return result
    }

    // MARK: - Folder Import

    func importFolders(urls: [URL], options: ImportOptions = .default) async throws -> (result: ImportResult, folderGroups: [(name: String, items: [MediaItem])]) {
        isLoading = true
        importCancelled = false
        defer {
            isLoading = false
            importProgress = nil
            updateItemCount()
            updateExternalItemCount()
        }

        // First pass: collect all files to get total count
        var allFolderFiles: [(name: String, fileURLs: [URL])] = []
        var looseFiles: [URL] = []
        var totalFileCount = 0

        for url in urls {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let mediaByFolder = collectMediaByFolder(in: url)
                for (folderName, fileURLs) in mediaByFolder {
                    allFolderFiles.append((name: folderName, fileURLs: fileURLs))
                    totalFileCount += fileURLs.count
                }
            } else {
                looseFiles.append(url)
            }
        }
        totalFileCount += looseFiles.count

        importProgress = ImportProgress(currentItem: 0, totalItems: totalFileCount, currentFilename: "", phase: .importing)

        var combinedResult = ImportResult()
        var folderGroups: [(name: String, items: [MediaItem])] = []
        var processedCount = 0

        // Import folder files
        for (folderName, fileURLs) in allFolderFiles {
            let importer = MediaImporter(libraryRoot: libraryRoot, externalLibraryRoot: externalLibraryRoot, modelContext: modelContainer.mainContext, options: options)
            let baseCount = processedCount
            let folderResult = try await importer.importFiles(urls: fileURLs) { [weak self] progress in
                Task { @MainActor in
                    guard self?.isLoading == true else { return }
                    self?.importProgress = ImportProgress(
                        currentItem: baseCount + progress.currentItem,
                        totalItems: totalFileCount,
                        currentFilename: progress.currentFilename,
                        phase: progress.phase
                    )
                }
            }
            combinedResult.merge(folderResult)
            processedCount += fileURLs.count
            if !folderResult.imported.isEmpty {
                folderGroups.append((name: folderName, items: folderResult.imported))
            }
        }

        // Import loose files
        if !looseFiles.isEmpty {
            let importer = MediaImporter(libraryRoot: libraryRoot, externalLibraryRoot: externalLibraryRoot, modelContext: modelContainer.mainContext, options: options)
            let baseCount = processedCount
            let looseResult = try await importer.importFiles(urls: looseFiles) { [weak self] progress in
                Task { @MainActor in
                    guard self?.isLoading == true else { return }
                    self?.importProgress = ImportProgress(
                        currentItem: baseCount + progress.currentItem,
                        totalItems: totalFileCount,
                        currentFilename: progress.currentFilename,
                        phase: progress.phase
                    )
                }
            }
            combinedResult.merge(looseResult)
        }

        if !combinedResult.imported.isEmpty {
            lastImportDate = Date()

            let videoItems = combinedResult.imported.filter { $0.isVideo }
            if !videoItems.isEmpty {
                let descriptor = FetchDescriptor<AppSettings>()
                let count = (try? modelContainer.mainContext.fetch(descriptor).first?.scrubThumbnailCount) ?? 100
                generateScrubThumbnailsForVideos(videoItems, count: count)
            }
        }

        Logger.library.info("Folder import complete: \(combinedResult.summary)")
        return (result: combinedResult, folderGroups: folderGroups)
    }

    private func collectMediaByFolder(in url: URL) -> [(name: String, fileURLs: [URL])] {
        var folderMap: [String: [URL]] = [:]

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            guard FileTypeDetector.isSupported(fileURL) else { continue }

            let parentDir = fileURL.deletingLastPathComponent()
            folderMap[parentDir.path, default: []].append(fileURL)
        }

        // Sort by folder path for consistent ordering, use folder name as the group name
        return folderMap.sorted { $0.key < $1.key }
            .map { (name: URL(fileURLWithPath: $0.key).lastPathComponent, fileURLs: $0.value) }
    }

    // MARK: - Delete

    func delete(_ item: MediaItem) {
        // Move file to Trash
        let fileURL = absoluteURL(for: item)
        try? fileManager.trashItem(at: fileURL, resultingItemURL: nil)

        // Delete thumbnails
        Task {
            await thumbnailCache.removeThumbnails(forHash: item.contentHash)
        }

        // Delete from database
        modelContainer.mainContext.delete(item)
        try? modelContainer.mainContext.save()

        updateItemCount()
        Logger.library.info("Trashed: \(item.originalFilename)")
        NotificationCenter.default.post(name: .mediaItemsDeleted, object: nil)
    }

    func delete(_ items: [MediaItem]) {
        for item in items {
            // Move file to Trash
            let fileURL = absoluteURL(for: item)
            try? fileManager.trashItem(at: fileURL, resultingItemURL: nil)

            // Delete thumbnails
            Task {
                await thumbnailCache.removeThumbnails(forHash: item.contentHash)
            }

            // Delete from database
            modelContainer.mainContext.delete(item)
        }
        try? modelContainer.mainContext.save()
        updateItemCount()
        Logger.library.info("Trashed \(items.count) items")
        NotificationCenter.default.post(name: .mediaItemsDeleted, object: nil)
    }

    // MARK: - Thumbnail Access

    func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> NSImage {
        let root = (item.storageLocation == .external && externalLibraryRoot != nil) ? externalLibraryRoot! : libraryRoot
        return try await thumbnailCache.thumbnail(for: item, size: size, libraryRoot: root)
    }

    func videoScrubThumbnails(for item: MediaItem, count: Int, size: ThumbnailSize) async throws -> [NSImage] {
        let root = (item.storageLocation == .external && externalLibraryRoot != nil) ? externalLibraryRoot! : libraryRoot
        return try await thumbnailCache.videoScrubThumbnails(for: item, count: count, size: size, libraryRoot: root)
    }

    // MARK: - Scrub Thumbnail Generation

    func generateScrubThumbnailsForVideos(_ items: [MediaItem], count: Int) {
        let cache = thumbnailCache

        let videoItems = items.filter { $0.isVideo }
            .map { PreGenerateItem(contentHash: $0.contentHash, fileURL: absoluteURL(for: $0), filename: $0.originalFilename) }

        guard !videoItems.isEmpty else { return }

        Task.detached(priority: .utility) {
            await cache.preGenerateScrubThumbnails(for: videoItems, count: count)
        }
    }

    func backgroundGenerateMissingScrubThumbnails(count: Int) {
        let cache = thumbnailCache

        let videoItems = allItems.filter { $0.isVideo }
            .map { PreGenerateItem(contentHash: $0.contentHash, fileURL: absoluteURL(for: $0), filename: $0.originalFilename) }

        guard !videoItems.isEmpty else { return }

        Task.detached(priority: .background) {
            await cache.preGenerateScrubThumbnails(for: videoItems, count: count)
        }
    }

    func invalidateScrubThumbnails(newCount: Int) {
        let cache = thumbnailCache

        Task.detached(priority: .utility) {
            await cache.clearScrubThumbnails()
        }

        // Re-generate with the new count
        backgroundGenerateMissingScrubThumbnails(count: newCount)
    }

    /// Regenerates scrub thumbnails with progress tracking.
    /// Returns the total number of videos to process.
    func regenerateScrubThumbnailsWithProgress(
        count: Int,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async -> Int {
        let cache = thumbnailCache

        // Clear existing scrub thumbnails first
        await cache.clearScrubThumbnails()

        let videoItems = allItems.filter { $0.isVideo }
            .map { PreGenerateItem(contentHash: $0.contentHash, fileURL: absoluteURL(for: $0), filename: $0.originalFilename) }

        let totalCount = videoItems.count

        guard totalCount > 0 else {
            return 0
        }

        await cache.preGenerateScrubThumbnails(
            for: videoItems,
            count: count
        ) { current, total in
            progress(current, total)
        }

        return totalCount
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

    var unplayableVideoCount: Int {
        allItems.filter { $0.isVideo && $0.hasThumbnailError }.count
    }

    func unplayableVideos(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        items(sortedBy: sortOrder, ascending: ascending)
            .filter { $0.isVideo && $0.hasThumbnailError }
    }

    // MARK: - Helpers

    private func updateItemCount() {
        let descriptor = FetchDescriptor<MediaItem>()
        itemCount = (try? modelContainer.mainContext.fetchCount(descriptor)) ?? 0
        libraryVersion += 1
    }

    func absoluteURL(for item: MediaItem) -> URL {
        switch item.storageLocation {
        case .referenced:
            return URL(fileURLWithPath: item.relativePath)
        case .external:
            if let extRoot = externalLibraryRoot {
                return extRoot.appendingPathComponent(item.relativePath)
            }
            // Fallback path that won't exist - caller should check accessibility
            return libraryRoot.appendingPathComponent("External/\(item.relativePath)")
        case .local:
            return libraryRoot.appendingPathComponent(item.relativePath)
        }
    }

    // MARK: - External Drive Support

    func configureExternalDrive(path: String?) {
        if let path, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            externalLibraryRoot = url
            isExternalDriveConnected = fileManager.fileExists(atPath: url.path)
        } else {
            externalLibraryRoot = nil
            isExternalDriveConnected = false
        }
        updateExternalItemCount()
        Logger.library.info("External drive configured: \(path ?? "none"), connected: \(self.isExternalDriveConnected)")
    }

    func refreshExternalDriveStatus() {
        if let extRoot = externalLibraryRoot {
            isExternalDriveConnected = fileManager.fileExists(atPath: extRoot.path)
        } else {
            isExternalDriveConnected = false
        }
        updateExternalItemCount()
    }

    private func updateExternalItemCount() {
        externalItemCount = items(in: .external).count
    }

    func locateExternalLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Locate the Slidr external library folder"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let descriptor = FetchDescriptor<AppSettings>()
        guard let settings = try? modelContainer.mainContext.fetch(descriptor).first else { return }

        settings.externalDrivePath = url.path
        try? modelContainer.mainContext.save()

        configureExternalDrive(path: url.path)
    }

    func isAccessible(_ item: MediaItem) -> Bool {
        if item.storageLocation == .external && !isExternalDriveConnected {
            return false
        }
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
            } else if item.storageLocation == .external && !isExternalDriveConnected {
                item.status = .externalNotMounted
                item.lastVerifiedDate = Date()
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
