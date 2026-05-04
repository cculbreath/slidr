import Foundation
import SwiftData
import OSLog

@MainActor
@Observable
final class PlaylistService {
    // MARK: - Published State
    private(set) var playlists: [Playlist] = []
    private(set) var lastError: Error?
    private(set) var playlistChangeGeneration: Int = 0

    // MARK: - Dependencies
    let modelContainer: ModelContainer
    let mediaLibrary: MediaLibrary

    // MARK: - Initialization

    init(modelContainer: ModelContainer, mediaLibrary: MediaLibrary) {
        self.modelContainer = modelContainer
        self.mediaLibrary = mediaLibrary

        loadPlaylists()
        observeMediaDeletions()
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
        }
    }

    func addItem(_ item: MediaItem, to playlist: Playlist) {
        guard playlist.isManualPlaylist else { return }
        playlist.addItem(item)
        save()
        loadPlaylists()
        playlistChangeGeneration += 1
        Logger.playlists.info("Added \(item.originalFilename) to \(playlist.name)")
    }

    func addItems(_ items: [MediaItem], to playlist: Playlist) {
        guard playlist.isManualPlaylist else { return }
        for item in items {
            playlist.addItem(item)
        }
        save()
        loadPlaylists()
        playlistChangeGeneration += 1
        Logger.playlists.info("Added \(items.count) items to \(playlist.name)")
    }

    func removeItem(_ item: MediaItem, from playlist: Playlist) {
        guard playlist.isManualPlaylist else { return }
        playlist.removeItem(item)
        save()
        loadPlaylists()
        playlistChangeGeneration += 1
        Logger.playlists.info("Removed \(item.originalFilename) from \(playlist.name)")
    }

    func moveItems(in playlist: Playlist, from source: IndexSet, to destination: Int) {
        guard playlist.isManualPlaylist else { return }
        playlist.moveItem(from: source, to: destination)
        save()
        playlistChangeGeneration += 1
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

        // Filter by production type
        if let productionTypes = playlist.filterProductionTypes, !productionTypes.isEmpty {
            let allowed = Set(productionTypes.compactMap { ProductionType(rawValue: $0) })
            filtered = filtered.filter { item in
                guard let production = item.production else { return false }
                return allowed.contains(production)
            }
        }

        // Filter by has transcript
        if let hasTranscript = playlist.filterHasTranscript, hasTranscript {
            filtered = filtered.filter { $0.hasTranscript }
        }

        // Filter by has caption
        if let hasCaption = playlist.filterHasCaption, hasCaption {
            filtered = filtered.filter { $0.hasCaption }
        }

        // Filter by included tags
        if let tags = playlist.filterTags, !tags.isEmpty {
            filtered = filtered.filter { item in
                tags.contains { tag in item.hasTag(tag) }
            }
        }

        // Filter by source
        if let sources = playlist.filterSources, !sources.isEmpty {
            filtered = filtered.filter { item in
                guard let itemSource = item.source?.lowercased() else { return false }
                return sources.contains { itemSource.contains($0.lowercased()) }
            }
        }

        // Filter by excluded tags
        if let excludedTags = playlist.filterTagsExcluded, !excludedTags.isEmpty {
            filtered = filtered.filter { item in
                !excludedTags.contains { tag in item.hasTag(tag) }
            }
        }

        // Filter by search text
        if let searchText = playlist.filterSearchText, !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter { item in
                item.originalFilename.lowercased().contains(query)
                    || item.tags.contains(where: { $0.lowercased().contains(query) })
                    || (item.caption?.lowercased().contains(query) ?? false)
            }
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
        withObservationTracking {
            _ = mediaLibrary.libraryVersion
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cleanupOrphanedItems()
                self?.observeMediaDeletions()
            }
        }
    }

}
