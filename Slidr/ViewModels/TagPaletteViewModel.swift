import Foundation

@MainActor
@Observable
final class TagPaletteViewModel {
    enum Mode: String, CaseIterable {
        case filter = "Filter"
        case editTags = "Edit Tags"
    }

    enum TagSort: String, CaseIterable {
        case alphabetical
        case byCount
    }

    var mode: Mode = .filter
    var searchText: String = ""
    var tagSort: TagSort = .alphabetical
    var sortAscending: Bool = true

    // External state (set by coordinator)
    var allTags: [String] = []
    var tagFilter: Set<String> = []
    var selectedItems: [MediaItem] = []
    var tagCounts: [String: Int] = [:]

    // Callbacks
    var onTagFilterChanged: ((Set<String>) -> Void)?
    var onShowAdvancedFilter: (() -> Void)?

    var filteredTags: [String] {
        let base = searchText.isEmpty ? allTags : allTags.filter { $0.localizedCaseInsensitiveContains(searchText) }
        switch tagSort {
        case .alphabetical:
            return sortAscending
                ? base.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                : base.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }
        case .byCount:
            return base.sorted { lhs, rhs in
                let lc = tagCounts[lhs] ?? 0
                let rc = tagCounts[rhs] ?? 0
                if lc == rc { return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending }
                return sortAscending ? lc < rc : lc > rc
            }
        }
    }

    func setSort(_ sort: TagSort) {
        if tagSort == sort {
            sortAscending.toggle()
        } else {
            tagSort = sort
            sortAscending = (sort == .alphabetical)
        }
    }

    // Tags common to ALL selected items (solid display)
    var commonTags: Set<String> {
        guard let first = selectedItems.first else { return [] }
        var common = Set(first.tags)
        for item in selectedItems.dropFirst() {
            common.formIntersection(item.tags)
        }
        return common
    }

    // Tags on ANY selected item (partial display — dimmed)
    var partialTags: Set<String> {
        Set(selectedItems.flatMap(\.tags))
    }

    // Filter mode
    func toggleFilterTag(_ tag: String) {
        if tagFilter.contains(tag) {
            tagFilter.remove(tag)
        } else {
            tagFilter.insert(tag)
        }
        onTagFilterChanged?(tagFilter)
    }

    func clearFilter() {
        tagFilter.removeAll()
        onTagFilterChanged?(tagFilter)
    }

    // Edit mode
    func addTagToSelected(_ tag: String) {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        for item in selectedItems { item.addTag(normalized) }
    }

    func removeTagFromSelected(_ tag: String) {
        for item in selectedItems { item.removeTag(tag) }
    }

    var hasSelection: Bool { !selectedItems.isEmpty }
}
