import SwiftUI
import SwiftData

@MainActor
@Observable
final class GridViewModel {
    // MARK: - State
    var selectedItems: Set<UUID> = []
    var thumbnailSize: ThumbnailSize = .medium
    var sortOrder: SortOrder = .dateImported
    var sortAscending: Bool = false

    // MARK: - Selection

    func select(_ item: MediaItem) {
        selectedItems = [item.id]
    }

    func toggleSelection(_ item: MediaItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }

    func extendSelection(to item: MediaItem, in items: [MediaItem]) {
        guard let lastSelected = selectedItems.first,
              let lastIndex = items.firstIndex(where: { $0.id == lastSelected }),
              let newIndex = items.firstIndex(where: { $0.id == item.id }) else {
            select(item)
            return
        }

        let range = min(lastIndex, newIndex)...max(lastIndex, newIndex)
        for i in range {
            selectedItems.insert(items[i].id)
        }
    }

    func selectAll(_ items: [MediaItem]) {
        selectedItems = Set(items.map(\.id))
    }

    func clearSelection() {
        selectedItems.removeAll()
    }

    func isSelected(_ item: MediaItem) -> Bool {
        selectedItems.contains(item.id)
    }

    // MARK: - Thumbnail Size

    var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize.pixelSize, maximum: thumbnailSize.pixelSize * 1.5), spacing: 8)]
    }
}
