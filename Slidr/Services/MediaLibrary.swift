import Foundation
import SwiftData
import AppKit
import OSLog

/// Main entry point for media library operations.
/// Acts as a facade delegating to specialized services.
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
    let transcriptStore: TranscriptStore
    private let fileManager = FileManager.default

    // MARK: - Sub-Services
    private let queryService: MediaQueryService
    private let importCoordinator: MediaImportCoordinator
    private let integrityService: LibraryIntegrityService

    // MARK: - Paths
    private(set) var libraryRoot: URL
    var externalLibraryRoot: URL?

    // MARK: - Initialization

    init(modelContainer: ModelContainer, thumbnailCache: ThumbnailCache, transcriptStore: TranscriptStore, libraryRoot: URL) {
        self.modelContainer = modelContainer
        self.thumbnailCache = thumbnailCache
        self.transcriptStore = transcriptStore
        self.libraryRoot = libraryRoot

        // Ensure directories exist
        try? fileManager.createDirectory(at: libraryRoot.appendingPathComponent("Local"), withIntermediateDirectories: true)

        // Initialize sub-services
        let queryService = MediaQueryService(modelContainer: modelContainer)
        self.queryService = queryService
        self.importCoordinator = MediaImportCoordinator(
            modelContainer: modelContainer,
            transcriptStore: transcriptStore,
            libraryRoot: libraryRoot
        )
        self.integrityService = LibraryIntegrityService(
            modelContainer: modelContainer,
            thumbnailCache: thumbnailCache,
            queryService: queryService
        )

        updateItemCount()
    }

    // MARK: - Queries

    var allItems: [MediaItem] { queryService.allItems }
    var allTags: [String] { queryService.allTags }
    var allSources: [String] { queryService.allSources }

    func items(matching predicate: Predicate<MediaItem>? = nil, sortedBy sortOrder: SortOrder = .dateImported, ascending: Bool = false) -> [MediaItem] {
        queryService.items(matching: predicate, sortedBy: sortOrder, ascending: ascending)
    }

    func items(inFolder folder: String, includeSubfolders: Bool) -> [MediaItem] {
        queryService.items(inFolder: folder, includeSubfolders: includeSubfolders)
    }

    func item(withHash hash: String) -> MediaItem? {
        queryService.item(withHash: hash)
    }

    func items(in location: StorageLocation) -> [MediaItem] {
        queryService.items(in: location)
    }

    // MARK: - Smart Albums

    func lastImportItems(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        guard let importDate = lastImportDate else { return [] }
        return queryService.lastImportItems(since: importDate, sortedBy: sortOrder, ascending: ascending)
    }

    func importedTodayItems(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        queryService.importedTodayItems(sortedBy: sortOrder, ascending: ascending)
    }

    var unplayableVideoCount: Int { queryService.unplayableVideoCount }

    func unplayableVideos(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        queryService.unplayableVideos(sortedBy: sortOrder, ascending: ascending)
    }

    var decodeErrorVideoCount: Int { queryService.decodeErrorVideoCount }

    func decodeErrorVideos(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        queryService.decodeErrorVideos(sortedBy: sortOrder, ascending: ascending)
    }

    // MARK: - Item Management

    func add(_ item: MediaItem) {
        modelContainer.mainContext.insert(item)
        try? modelContainer.mainContext.save()
        updateItemCount()
    }

    // MARK: - Import

    func cancelImport() {
        importCancelled = true
        isLoading = false
        importProgress = nil
        Logger.library.info("Import cancelled by user")
    }

    func importFiles(urls: [URL], options: ImportOptions = ImportOptions()) async throws -> ImportResult {
        isLoading = true
        importCancelled = false
        importProgress = ImportProgress(currentItem: 0, totalItems: urls.count, currentFilename: "", phase: .importing)
        defer {
            isLoading = false
            importProgress = nil
            updateItemCount()
            updateExternalItemCount()
        }

        let result = try await importCoordinator.importFiles(urls: urls, options: options) { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                guard self.isLoading else { return }
                self.importProgress = progress
            }
        }

        handlePostImport(result: result)
        Logger.library.info("Import complete: \(result.summary)")
        return result
    }

    func importFolders(urls: [URL], options: ImportOptions = ImportOptions()) async throws -> (result: ImportResult, folderGroups: [(name: String, items: [MediaItem])]) {
        isLoading = true
        importCancelled = false
        defer {
            isLoading = false
            importProgress = nil
            updateItemCount()
            updateExternalItemCount()
        }

        let (result, folderGroups) = try await importCoordinator.importFolders(urls: urls, options: options) { [weak self] progress in
            guard let self else { return }
            Task { @MainActor in
                guard self.isLoading else { return }
                self.importProgress = progress
            }
        }

        handlePostImport(result: result)
        Logger.library.info("Folder import complete: \(result.summary)")
        return (result: result, folderGroups: folderGroups)
    }

    func importSubtitles(urls: [URL]) async -> SubtitleImportResult {
        let videoItems = allItems.filter { $0.isVideo }
        return await importCoordinator.importSubtitles(urls: urls, videoItems: videoItems)
    }

    func copyToLibrary(_ item: MediaItem) async throws {
        try await importCoordinator.copyToLibrary(item)
    }

    private func handlePostImport(result: ImportResult) {
        guard !result.imported.isEmpty else { return }
        lastImportDate = Date()

        let videoItems = result.imported.filter { $0.isVideo }
        if !videoItems.isEmpty {
            let descriptor = FetchDescriptor<AppSettings>()
            let count = (try? modelContainer.mainContext.fetch(descriptor).first?.scrubThumbnailCount) ?? 100
            generateScrubThumbnailsForVideos(videoItems, count: count)
        }
    }

    // MARK: - Delete

    func delete(_ item: MediaItem) {
        let fileURL = absoluteURL(for: item)
        try? fileManager.trashItem(at: fileURL, resultingItemURL: nil)

        Task { await thumbnailCache.removeThumbnails(forHash: item.contentHash) }

        if let relativePath = item.transcriptRelativePath {
            Task { await transcriptStore.removeTranscript(forContentHash: item.contentHash, relativePath: relativePath) }
        }

        modelContainer.mainContext.delete(item)
        try? modelContainer.mainContext.save()

        updateItemCount()
        Logger.library.info("Trashed: \(item.originalFilename)")
    }

    func delete(_ items: [MediaItem]) {
        for item in items {
            let fileURL = absoluteURL(for: item)
            try? fileManager.trashItem(at: fileURL, resultingItemURL: nil)

            Task { await thumbnailCache.removeThumbnails(forHash: item.contentHash) }

            if let relativePath = item.transcriptRelativePath {
                Task { await transcriptStore.removeTranscript(forContentHash: item.contentHash, relativePath: relativePath) }
            }

            modelContainer.mainContext.delete(item)
        }
        try? modelContainer.mainContext.save()
        updateItemCount()
        Logger.library.info("Trashed \(items.count) items")
    }

    // MARK: - Thumbnail Access

    func thumbnail(for item: MediaItem, size: ThumbnailSize) async throws -> NSImage {
        let root = (item.storageLocation == .external) ? (externalLibraryRoot ?? libraryRoot) : libraryRoot
        return try await thumbnailCache.thumbnail(for: item, size: size, libraryRoot: root)
    }

    func videoScrubThumbnails(for item: MediaItem, count: Int, size: ThumbnailSize) async throws -> [NSImage] {
        let root = (item.storageLocation == .external) ? (externalLibraryRoot ?? libraryRoot) : libraryRoot
        return try await thumbnailCache.videoScrubThumbnails(for: item, count: count, size: size, libraryRoot: root)
    }

    // MARK: - Scrub Thumbnail Generation

    func generateScrubThumbnailsForVideos(_ items: [MediaItem], count: Int) {
        let cache = thumbnailCache
        let videoItems = items.filter { $0.isVideo }
            .map { PreGenerateItem(contentHash: $0.contentHash, fileURL: absoluteURL(for: $0), filename: $0.originalFilename) }

        guard !videoItems.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            let failedHashes = await cache.preGenerateScrubThumbnails(for: videoItems, count: count)
            if !failedHashes.isEmpty {
                await self?.markDecodeErrors(forHashes: failedHashes)
            }
        }
    }

    func backgroundGenerateMissingScrubThumbnails(count: Int) {
        let cache = thumbnailCache
        let videoItems = allItems.filter { $0.isVideo && !$0.hasDecodeError }
            .map { PreGenerateItem(contentHash: $0.contentHash, fileURL: absoluteURL(for: $0), filename: $0.originalFilename) }

        guard !videoItems.isEmpty else { return }

        Task.detached(priority: .background) { [weak self] in
            let failedHashes = await cache.preGenerateScrubThumbnails(for: videoItems, count: count)
            if !failedHashes.isEmpty {
                await self?.markDecodeErrors(forHashes: failedHashes)
            }
        }
    }

    func invalidateScrubThumbnails(newCount: Int) {
        let cache = thumbnailCache
        Task.detached(priority: .utility) {
            await cache.clearScrubThumbnails()
        }
        backgroundGenerateMissingScrubThumbnails(count: newCount)
    }

    func regenerateScrubThumbnailsWithProgress(
        count: Int,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async -> Int {
        let cache = thumbnailCache
        await cache.clearScrubThumbnails()

        let videoItems = allItems.filter { $0.isVideo }
            .map { PreGenerateItem(contentHash: $0.contentHash, fileURL: absoluteURL(for: $0), filename: $0.originalFilename) }

        let totalCount = videoItems.count
        guard totalCount > 0 else { return 0 }

        let failedHashes = await cache.preGenerateScrubThumbnails(
            for: videoItems,
            count: count
        ) { current, total in
            progress(current, total)
        }

        if !failedHashes.isEmpty {
            markDecodeErrors(forHashes: failedHashes)
        }

        return totalCount
    }

    // MARK: - Decode Error Retry

    func retryDecodeErrorThumbnails(
        for items: [MediaItem],
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async -> Int {
        let cache = thumbnailCache
        let descriptor = FetchDescriptor<AppSettings>()
        let count = (try? modelContainer.mainContext.fetch(descriptor).first?.scrubThumbnailCount) ?? 100

        // Clear existing scrub thumbnails for these items so they get regenerated
        for item in items {
            await cache.removeThumbnails(forHash: item.contentHash)
        }

        let pregenItems = items.map {
            PreGenerateItem(contentHash: $0.contentHash, fileURL: absoluteURL(for: $0), filename: $0.originalFilename)
        }

        let failedHashes = await cache.preGenerateScrubThumbnails(
            for: pregenItems,
            count: count
        ) { current, total in
            progress(current, total)
        }

        // Clear decode error flag for items that succeeded
        var recovered = 0
        for item in items {
            if !failedHashes.contains(item.contentHash) {
                item.hasDecodeError = false
                recovered += 1
            }
        }

        if recovered > 0 {
            try? modelContainer.mainContext.save()
            libraryVersion += 1
            Logger.library.info("Recovered \(recovered) video(s) from decode errors")
        }

        return recovered
    }

    // MARK: - Library Path Management

    func setLibraryRoot(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }

        let localDir = url.appendingPathComponent("Local", isDirectory: true)
        try fileManager.createDirectory(at: localDir, withIntermediateDirectories: true)

        libraryRoot = url
        importCoordinator.libraryRoot = url
        Logger.library.info("Library root changed to: \(url.path)")
    }

    func migrateLibrary(to newPath: URL, progress: ((Double) -> Void)? = nil) async throws {
        let oldPath = libraryRoot
        guard oldPath != newPath else { return }

        let oldLocalDir = oldPath.appendingPathComponent("Local")
        guard let files = try? fileManager.contentsOfDirectory(at: oldLocalDir, includingPropertiesForKeys: nil) else { return }

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
        importCoordinator.libraryRoot = newPath
        Logger.library.info("Library migrated from \(oldPath.path) to \(newPath.path)")
    }

    // MARK: - External Drive Support

    func configureExternalDrive(path: String?) {
        if let path, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            externalLibraryRoot = url
            importCoordinator.externalLibraryRoot = url
            isExternalDriveConnected = fileManager.fileExists(atPath: url.path)
        } else {
            externalLibraryRoot = nil
            importCoordinator.externalLibraryRoot = nil
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

    // MARK: - Verification

    func verifyLibraryIntegrity() async -> VerificationResult {
        await integrityService.verifyIntegrity(
            urlResolver: { [self] item in absoluteURL(for: item) },
            isExternalDriveConnected: isExternalDriveConnected
        )
    }

    func cleanOrphanedThumbnails() async {
        await integrityService.cleanOrphanedThumbnails()
    }

    func removeOrphanedItems() {
        integrityService.removeOrphanedItems()
        updateItemCount()
    }

    // MARK: - Helpers

    func absoluteURL(for item: MediaItem) -> URL {
        switch item.storageLocation {
        case .referenced:
            return URL(fileURLWithPath: item.relativePath)
        case .external:
            if let extRoot = externalLibraryRoot {
                return extRoot.appendingPathComponent(item.relativePath)
            }
            return libraryRoot.appendingPathComponent("External/\(item.relativePath)")
        case .local:
            return libraryRoot.appendingPathComponent(item.relativePath)
        }
    }

    private func markDecodeErrors(forHashes hashes: Set<String>) {
        var marked = 0
        for hash in hashes {
            if let item = queryService.item(withHash: hash), !item.hasDecodeError {
                item.hasDecodeError = true
                marked += 1
            }
        }
        if marked > 0 {
            try? modelContainer.mainContext.save()
            Logger.library.info("Marked \(marked) video(s) with decode errors")
        }
    }

    private func updateItemCount() {
        itemCount = queryService.fetchCount()
        libraryVersion += 1
    }

    private func updateExternalItemCount() {
        externalItemCount = queryService.items(in: .external).count
    }
}
