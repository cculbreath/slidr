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

    // MARK: - Filter
    var mediaTypeFilter: Set<MediaType> = []
    var productionTypeFilter: Set<ProductionType> = []
    var tagFilter: Set<String> = []

    // Rating filter: nil means include all, empty set with enabled means show nothing
    var ratingFilterEnabled: Bool = false
    var ratingFilter: Set<Int> = [] // 0-5, where 0 means "no rating"
    var subtitleFilter: Bool = false
    var captionFilter: Bool = false
    var advancedFilter: AdvancedFilter?

    // MARK: - Search
    var searchText: String = ""
    var isSearchFocused: Bool = false

    // MARK: - Keyboard Navigation
    var focusedIndex: Int? = nil

    // MARK: - Delete State
    var itemsToDelete: [MediaItem] = []
    var showDeleteConfirmation = false

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

    // MARK: - Search

    func filteredItems(_ items: [MediaItem]) -> [MediaItem] {
        var result = items

        if !mediaTypeFilter.isEmpty {
            result = result.filter { mediaTypeFilter.contains($0.mediaType) }
        }

        if !productionTypeFilter.isEmpty {
            result = result.filter { item in
                guard let production = item.production else { return false }
                return productionTypeFilter.contains(production)
            }
        }

        if !tagFilter.isEmpty {
            result = result.filter { item in
                tagFilter.contains { tag in item.hasTag(tag) }
            }
        }

        if ratingFilterEnabled && !ratingFilter.isEmpty {
            result = result.filter { item in
                let itemRating = item.rating ?? 0
                // 0 in filter means "no rating" (nil or 0)
                if ratingFilter.contains(0) && (item.rating == nil || item.rating == 0) {
                    return true
                }
                // 1-5 means that specific rating
                return ratingFilter.contains(itemRating)
            }
        }

        if subtitleFilter {
            result = result.filter { $0.hasTranscript }
        }

        if captionFilter {
            result = result.filter { $0.hasCaption }
        }

        if let advancedFilter, !advancedFilter.isEmpty {
            result = result.filter { advancedFilter.matches($0) }
        }

        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        return result.filter { item in
            if item.originalFilename.lowercased().contains(query) { return true }
            if item.tags.contains(where: { $0.lowercased().contains(query) }) { return true }
            if let caption = item.caption?.lowercased(), caption.contains(query) { return true }
            if let transcript = item.transcriptText?.lowercased(), transcript.contains(query) { return true }
            if let summary = item.summary?.lowercased(), summary.contains(query) { return true }
            return false
        }
    }

    func clearSearch() {
        searchText = ""
    }

    func clearAllFilters() {
        mediaTypeFilter = []
        productionTypeFilter = []
        tagFilter = []
        ratingFilterEnabled = false
        ratingFilter = []
        subtitleFilter = false
        captionFilter = false
        advancedFilter = nil
        searchText = ""
        sortOrder = .dateImported
        sortAscending = false
    }

    func clearAdvancedFilter() {
        advancedFilter = nil
    }

    // MARK: - Keyboard Navigation

    func moveSelection(direction: NavigationDirection, in items: [MediaItem], columns: Int) {
        guard !items.isEmpty else { return }
        let currentIndex = focusedIndex ?? (selectedItems.first.flatMap { id in
            items.firstIndex { $0.id == id }
        }) ?? 0

        let newIndex: Int
        switch direction {
        case .up: newIndex = max(0, currentIndex - columns)
        case .down: newIndex = min(items.count - 1, currentIndex + columns)
        case .left: newIndex = max(0, currentIndex - 1)
        case .right: newIndex = min(items.count - 1, currentIndex + 1)
        }

        focusedIndex = newIndex
        selectedItems = [items[newIndex].id]
    }

    func increaseThumbnailSize() {
        let sizes = ThumbnailSize.allCases
        guard let currentIndex = sizes.firstIndex(of: thumbnailSize),
              currentIndex < sizes.count - 1 else { return }
        thumbnailSize = sizes[currentIndex + 1]
    }

    func decreaseThumbnailSize() {
        let sizes = ThumbnailSize.allCases
        guard let currentIndex = sizes.firstIndex(of: thumbnailSize),
              currentIndex > 0 else { return }
        thumbnailSize = sizes[currentIndex - 1]
    }

    func resetThumbnailSize() {
        thumbnailSize = .medium
    }

    func columnCount(for containerWidth: CGFloat) -> Int {
        let itemWidth = thumbnailSize.pixelSize + 8
        return max(1, Int(containerWidth / itemWidth))
    }

    // MARK: - Delete

    func prepareDelete(items: [MediaItem], confirmBeforeDelete: Bool) {
        itemsToDelete = items
        if confirmBeforeDelete && !items.isEmpty {
            showDeleteConfirmation = true
        }
    }

    func cancelDelete() {
        itemsToDelete = []
        showDeleteConfirmation = false
    }

    // MARK: - Thumbnail Size

    var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize.pixelSize, maximum: thumbnailSize.pixelSize * 1.5), spacing: 8)]
    }
}

// MARK: - Navigation Direction

enum NavigationDirection {
    case up, down, left, right
}
