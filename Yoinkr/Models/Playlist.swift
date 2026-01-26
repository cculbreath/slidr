import SwiftData
import Foundation

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: PlaylistType
    var createdDate: Date
    var modifiedDate: Date

    // Sorting
    var sortOrder: SortOrder
    var sortAscending: Bool

    // Manual playlist items (stored as UUIDs for Phase 1)
    var itemIDs: [UUID]

    init(name: String, type: PlaylistType) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.sortOrder = .dateImported
        self.sortAscending = false
        self.itemIDs = []
    }
}
