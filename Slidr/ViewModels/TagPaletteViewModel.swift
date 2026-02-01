import Foundation

@MainActor
@Observable
final class TagPaletteViewModel {
    enum Mode: String, CaseIterable {
        case filter = "Filter"
        case editTags = "Edit Tags"
    }

    var mode: Mode = .filter
    var searchText: String = ""

    // External state (set by coordinator)
    var allTags: [String] = []
    var tagFilter: Set<String> = []
    var selectedItems: [MediaItem] = []

    // Callback to push filter changes back to GridViewModel
    var onTagFilterChanged: ((Set<String>) -> Void)?

    var filteredTags: [String] {
        if searchText.isEmpty { return allTags }
        return allTags.filter { $0.localizedCaseInsensitiveContains(searchText) }
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
