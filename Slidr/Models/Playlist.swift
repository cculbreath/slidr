import SwiftData
import SwiftUI
import Foundation

@Model
final class Playlist {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID
    var name: String
    var type: PlaylistType
    var createdDate: Date
    var modifiedDate: Date

    // MARK: - Sorting
    var sortOrder: SortOrder
    var sortAscending: Bool

    // MARK: - Manual Playlist Items
    @Relationship(deleteRule: .nullify, inverse: \MediaItem.playlists)
    var manualItems: [MediaItem]?

    /// Ordered UUIDs for manual playlists to preserve user-defined ordering
    var manualItemOrder: [UUID]

    // MARK: - Smart Playlist Properties
    var watchedFolderPath: String?
    var includeSubfolders: Bool

    // MARK: - Filter Properties
    var filterMinDuration: TimeInterval?
    var filterMaxDuration: TimeInterval?
    var filterMediaTypes: [String]?
    var filterFavoritesOnly: Bool
    var filterMinRating: Int?
    var filterProductionTypes: [String]?
    var filterHasTranscript: Bool?
    var filterHasCaption: Bool?
    var filterTags: [String]?
    var filterTagsExcluded: [String]?
    var filterSearchText: String?
    var filterSources: [String]?

    // MARK: - Display Properties
    var iconName: String?
    var colorHex: String?

    // MARK: - Initialization
    init(name: String, type: PlaylistType) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.sortOrder = .dateImported
        self.sortAscending = false
        self.manualItems = []
        self.manualItemOrder = []
        self.includeSubfolders = true
        self.filterFavoritesOnly = false
        self.filterMinRating = nil
    }

    // MARK: - Computed Properties

    var isSmartPlaylist: Bool {
        type == .smart
    }

    var isManualPlaylist: Bool {
        type == .manual
    }

    var watchedFolderURL: URL? {
        guard let path = watchedFolderPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var allowedMediaTypes: [MediaType] {
        guard let typeStrings = filterMediaTypes else { return MediaType.allCases }
        return typeStrings.compactMap { MediaType(rawValue: $0) }
    }

    /// Returns manual items in the user-defined order specified by `manualItemOrder`
    var orderedManualItems: [MediaItem] {
        guard let items = manualItems else { return [] }
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        // Return items in order, skipping any IDs that no longer exist
        var ordered = manualItemOrder.compactMap { itemsByID[$0] }
        // Append any items that exist but aren't in the order array
        let orderedIDs = Set(manualItemOrder)
        let unordered = items.filter { !orderedIDs.contains($0.id) }
        ordered.append(contentsOf: unordered)
        return ordered
    }

    // MARK: - Manual Playlist Management

    func addItem(_ item: MediaItem) {
        guard type == .manual else { return }
        if manualItems == nil { manualItems = [] }
        guard !(manualItems?.contains(where: { $0.id == item.id }) ?? false) else { return }
        manualItems?.append(item)
        manualItemOrder.append(item.id)
        modifiedDate = Date()
    }

    func removeItem(_ item: MediaItem) {
        guard type == .manual else { return }
        manualItems?.removeAll { $0.id == item.id }
        manualItemOrder.removeAll { $0 == item.id }
        modifiedDate = Date()
    }

    func moveItem(from source: IndexSet, to destination: Int) {
        guard type == .manual else { return }
        manualItemOrder.move(fromOffsets: source, toOffset: destination)
        modifiedDate = Date()
    }

    /// Remove references to items that no longer exist in the library
    func removeOrphanedItems(existingIDs: Set<UUID>) {
        manualItems?.removeAll { !existingIDs.contains($0.id) }
        manualItemOrder.removeAll { !existingIDs.contains($0) }
        modifiedDate = Date()
    }
}
