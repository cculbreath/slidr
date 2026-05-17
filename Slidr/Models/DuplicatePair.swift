import Foundation

/// A candidate pair of media items flagged as visually similar.
/// Produced by `DuplicateDetectionService`, consumed by the duplicate review UI.
///
/// Carries Sendable `MediaItemSnapshot`s for display, and the underlying
/// `MediaItem` references for the eventual delete operation. The review UI
/// reads from snapshots only — that way SwiftUI's deferred render/hover
/// updates can't crash on a tombstoned `@Model` after the user trashes one
/// side of a pair.
struct DuplicatePair: Identifiable, Hashable {
    let id: UUID
    let snapshotA: MediaItemSnapshot
    let snapshotB: MediaItemSnapshot
    /// Vision feature-print distance. Lower = more similar.
    let distance: Float

    /// Live `@Model` references. Only the review handler should touch these,
    /// and only to call `library.delete(_:)` — never read any of their
    /// `@Attribute` properties from view code.
    let itemA: MediaItem
    let itemB: MediaItem

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

    static func == (lhs: DuplicatePair, rhs: DuplicatePair) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
