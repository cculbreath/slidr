import Foundation
import SwiftData
import UniformTypeIdentifiers
import OSLog

extension Notification.Name {
    static let playlistItemsChanged = Notification.Name("com.physicscloud.slidr.playlistItemsChanged")
}

@MainActor
@Observable
final class PlaylistService {
    // MARK: - Published State
    private(set) var playlists: [Playlist] = []
    private(set) var lastError: Error?

    // MARK: - Dependencies
    let modelContainer: ModelContainer
    let mediaLibrary: MediaLibrary
    let folderWatcher: FolderWatcher

    private var deletionObserver: NSObjectProtocol?

    // MARK: - Initialization

    init(modelContainer: ModelContainer, mediaLibrary: MediaLibrary, folderWatcher: FolderWatcher) {
        self.modelContainer = modelContainer
        self.mediaLibrary = mediaLibrary
        self.folderWatcher = folderWatcher

        loadPlaylists()
        observeMediaDeletions()
    }

    nonisolated deinit {
    }

    // MARK: - CRUD

    @discardableResult
    func createPlaylist(name: String, type: PlaylistType) -> Playlist {
        let playlist = Playlist(name: name, type: type)
        modelContainer.mainContext.insert(playlist)
        save()
        loadPlaylists()
        Logger.playlists.info("Created playlist: \(name) (\(type.rawValue))")
        return playlist
    }

    func updatePlaylist(_ playlist: Playlist) {
        playlist.modifiedDate = Date()
        save()
        loadPlaylists()
        Logger.playlists.info("Updated playlist: \(playlist.name)")
    }

    func deletePlaylist(_ playlist: Playlist) {
        // Stop watching if this is a smart playlist with a watched folder
        if let folderURL = playlist.watchedFolderURL {
            Task {
                await folderWatcher.stopWatching(url: folderURL)
            }
        }
        let name = playlist.name
        modelContainer.mainContext.delete(playlist)
        save()
        loadPlaylists()
        Logger.playlists.info("Deleted playlist: \(name)")
    }

    // MARK: - Item Management

    func items(for playlist: Playlist) -> [MediaItem] {
        switch playlist.type {
        case .allMedia:
            return filteredAndSorted(items: mediaLibrary.allItems, playlist: playlist)
        case .manual:
            return filteredAndSorted(items: playlist.orderedManualItems, playlist: playlist)
        case .smart:
            return filteredAndSorted(items: mediaLibrary.allItems, playlist: playlist)
        }
    }

    func addItem(_ item: MediaItem, to playlist: Playlist) {
        guard playlist.isManualPlaylist else { return }
        playlist.addItem(item)
        save()
        loadPlaylists()
        NotificationCenter.default.post(name: .playlistItemsChanged, object: playlist.id)
        Logger.playlists.info("Added \(item.originalFilename) to \(playlist.name)")
    }

    func addItems(_ items: [MediaItem], to playlist: Playlist) {
        guard playlist.isManualPlaylist else { return }
        for item in items {
            playlist.addItem(item)
        }
        save()
        loadPlaylists()
        NotificationCenter.default.post(name: .playlistItemsChanged, object: playlist.id)
        Logger.playlists.info("Added \(items.count) items to \(playlist.name)")
    }

    func removeItem(_ item: MediaItem, from playlist: Playlist) {
        guard playlist.isManualPlaylist else { return }
        playlist.removeItem(item)
        save()
        loadPlaylists()
        NotificationCenter.default.post(name: .playlistItemsChanged, object: playlist.id)
        Logger.playlists.info("Removed \(item.originalFilename) from \(playlist.name)")
    }

    func moveItems(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        guard playlist.isManualPlaylist else { return }
        playlist.moveItem(from: source, to: destination)
        save()
        NotificationCenter.default.post(name: .playlistItemsChanged, object: playlist.id)
    }

    // MARK: - Smart Playlist

    func setWatchedFolder(_ url: URL?, for playlist: Playlist) {
        guard playlist.isSmartPlaylist else { return }

        // Stop previous watcher if any
        if let previousURL = playlist.watchedFolderURL {
            Task {
                await folderWatcher.stopWatching(url: previousURL)
            }
        }

        playlist.watchedFolderPath = url?.path
        playlist.modifiedDate = Date()
        save()

        if let url = url {
            startWatching(url: url, playlist: playlist)
            Task {
                await scanWatchedFolder(url: url, playlist: playlist)
            }
        }

        Logger.playlists.info("Set watched folder for \(playlist.name): \(url?.path ?? "none")")
    }

    func scanWatchedFolder(url: URL, playlist: Playlist) async {
        let filesToImport = collectMatchingFiles(in: url, playlist: playlist)

        guard !filesToImport.isEmpty else {
            Logger.playlists.info("No matching files in watched folder: \(url.path)")
            return
        }

        do {
            let result = try await mediaLibrary.importFiles(urls: filesToImport)
            Logger.playlists.info("Scanned watched folder \(url.path): \(result.summary)")
        } catch {
            Logger.playlists.error("Failed to import from watched folder: \(error.localizedDescription)")
            lastError = error
        }
    }

    private func collectMatchingFiles(in url: URL, playlist: Playlist) -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            Logger.playlists.warning("Watched folder does not exist: \(url.path)")
            return []
        }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        if !playlist.includeSubfolders {
            options.insert(.skipsSubdirectoryDescendants)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
            options: options
        ) else {
            Logger.playlists.error("Failed to enumerate folder: \(url.path)")
            return []
        }

        var filesToImport: [URL] = []
        let allowedTypes = playlist.allowedMediaTypes

        while let fileURL = enumerator.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
                  resourceValues.isRegularFile == true,
                  let contentType = resourceValues.contentType else {
                continue
            }

            let isAllowed = allowedTypes.contains { mediaType in
                switch mediaType {
                case .image:
                    return contentType.conforms(to: .image) && !contentType.conforms(to: .gif)
                case .gif:
                    return contentType.conforms(to: .gif)
                case .video:
                    return contentType.conforms(to: .movie) || contentType.conforms(to: .video)
                }
            }

            if isAllowed {
                filesToImport.append(fileURL)
            }
        }

        return filesToImport
    }

    // MARK: - Filtering & Sorting

    func filteredAndSorted(items: [MediaItem], playlist: Playlist) -> [MediaItem] {
        var filtered = items

        // Filter by media type
        if let typeStrings = playlist.filterMediaTypes, !typeStrings.isEmpty {
            let allowedTypes = Set(typeStrings.compactMap { MediaType(rawValue: $0) })
            filtered = filtered.filter { allowedTypes.contains($0.mediaType) }
        }

        // Filter by favorites
        if playlist.filterFavoritesOnly {
            filtered = filtered.filter { $0.isFavorite }
        }

        // Filter by minimum duration
        if let minDuration = playlist.filterMinDuration {
            filtered = filtered.filter { ($0.duration ?? 0) >= minDuration }
        }

        // Filter by maximum duration
        if let maxDuration = playlist.filterMaxDuration {
            filtered = filtered.filter { ($0.duration ?? 0) <= maxDuration }
        }

        // Apply sorting (manual playlists preserve order unless explicitly sorted)
        if playlist.isManualPlaylist && playlist.sortOrder == .dateImported && !playlist.sortAscending {
            // Default sort for manual playlists = manual order (no re-sort)
            return filtered
        }

        return sorted(items: filtered, by: playlist.sortOrder, ascending: playlist.sortAscending)
    }

    func sorted(items: [MediaItem], by sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        switch sortOrder {
        case .name:
            return items.sorted {
                ascending
                    ? $0.originalFilename.localizedStandardCompare($1.originalFilename) == .orderedAscending
                    : $0.originalFilename.localizedStandardCompare($1.originalFilename) == .orderedDescending
            }
        case .dateModified:
            return items.sorted {
                ascending ? $0.fileModifiedDate < $1.fileModifiedDate : $0.fileModifiedDate > $1.fileModifiedDate
            }
        case .dateImported:
            return items.sorted {
                ascending ? $0.importDate < $1.importDate : $0.importDate > $1.importDate
            }
        case .fileSize:
            return items.sorted {
                ascending ? $0.fileSize < $1.fileSize : $0.fileSize > $1.fileSize
            }
        case .duration:
            return items.sorted {
                let d0 = $0.duration ?? 0
                let d1 = $1.duration ?? 0
                return ascending ? d0 < d1 : d0 > d1
            }
        }
    }

    // MARK: - Orphan Cleanup

    func cleanupOrphanedItems() {
        let allItemIDs = Set(mediaLibrary.allItems.map { $0.id })
        for playlist in playlists where playlist.isManualPlaylist {
            playlist.removeOrphanedItems(existingIDs: allItemIDs)
        }
        save()
        Logger.playlists.info("Cleaned up orphaned playlist items")
    }

    // MARK: - Queries

    func loadPlaylists() {
        let descriptor = FetchDescriptor<Playlist>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        playlists = (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    func playlist(withID id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    // MARK: - Private

    private func save() {
        do {
            try modelContainer.mainContext.save()
        } catch {
            Logger.playlists.error("Failed to save context: \(error.localizedDescription)")
            lastError = error
        }
    }

    private func observeMediaDeletions() {
        deletionObserver = NotificationCenter.default.addObserver(
            forName: .mediaItemsDeleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.cleanupOrphanedItems()
            }
        }
    }

    private func startWatching(url: URL, playlist: Playlist) {
        let playlistID = playlist.id
        Task {
            await folderWatcher.watch(url: url, includeSubfolders: playlist.includeSubfolders) { [weak self] eventURL, eventType in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.handleFolderEvent(url: eventURL, type: eventType, playlistID: playlistID)
                }
            }
        }
    }

    private func handleFolderEvent(url: URL, type: FSEventType, playlistID: UUID) {
        guard let playlist = playlist(withID: playlistID),
              playlist.isSmartPlaylist else { return }

        switch type {
        case .created, .renamed:
            // Import new file if it matches allowed types
            let ext = url.pathExtension.lowercased()
            guard let uti = UTType(filenameExtension: ext) else { return }
            let isMedia = uti.conforms(to: .image) || uti.conforms(to: .movie) || uti.conforms(to: .video)
            guard isMedia else { return }

            Task {
                do {
                    _ = try await mediaLibrary.importFiles(urls: [url])
                    Logger.playlists.info("Auto-imported from watched folder: \(url.lastPathComponent)")
                } catch {
                    Logger.playlists.error("Auto-import failed: \(error.localizedDescription)")
                }
            }

        case .modified:
            // No action needed for modifications to already-imported files
            break

        case .deleted:
            // File deletion from watched folder doesn't remove from library
            // (user may want to keep imported copies)
            Logger.playlists.info("File deleted from watched folder: \(url.lastPathComponent)")
        }
    }
}
