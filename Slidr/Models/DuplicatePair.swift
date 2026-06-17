import Foundation

/// A candidate pair of media items flagged as visually similar.
/// Produced by `DuplicateDetectionService`, consumed by the duplicate review UI.
///
/// The pair exposes Sendable snapshots for view code, and keeps the underlying
/// `@Model` references private so callers can't accidentally read attributes
/// from a tombstoned model after a delete. Use `delete(side:in:)` /
/// `deleteBoth(in:)` to dispose of items.
struct DuplicatePair: Identifiable, Hashable {
    enum Side { case left, right }

    let id: UUID
    let snapshotA: MediaItemSnapshot
    let snapshotB: MediaItemSnapshot
    /// Vision feature-print distance. Lower = more similar.
    let distance: Float

    private let itemA: MediaItem
    private let itemB: MediaItem

    /// Live model references for the items that would be removed by
    /// `delete(side:in:)` / `deleteBoth(in:)`. Pass these to
    /// `DuplicateDetectionService.removePairs(referencing:)` before the
    /// delete lands so SwiftUI can't re-render a tombstoned model.
    var members: [MediaItem] { [itemA, itemB] }

    @MainActor
    init(itemA: MediaItem, itemB: MediaItem, distance: Float) {
        self.id = UUID()
        // Stable ordering so the same pair always presents A/B the same way.
        if itemA.id.uuidString < itemB.id.uuidString {
            self.itemA = itemA
            self.itemB = itemB
            self.snapshotA = MediaItemSnapshot.capture(itemA)
            self.snapshotB = MediaItemSnapshot.capture(itemB)
        } else {
            self.itemA = itemB
            self.itemB = itemA
            self.snapshotA = MediaItemSnapshot.capture(itemB)
            self.snapshotB = MediaItemSnapshot.capture(itemA)
        }
        self.distance = distance
    }

    /// Trash the item on the chosen side. Returns the item that was deleted
    /// so the caller can strip every pair referencing it from the review list.
    @MainActor
    func delete(side: Side, in library: MediaLibrary) -> MediaItem {
        let target = side == .left ? itemA : itemB
        library.delete(target)
        return target
    }

    @MainActor
    func deleteBoth(in library: MediaLibrary) {
        library.delete([itemA, itemB])
    }

    static func == (lhs: DuplicatePair, rhs: DuplicatePair) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
