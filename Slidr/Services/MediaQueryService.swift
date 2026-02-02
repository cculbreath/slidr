import Foundation
import SwiftData
import OSLog

/// Service responsible for querying and filtering media items from the database.
@MainActor
final class MediaQueryService {
    private let modelContainer: ModelContainer
    private var modelContext: ModelContext { modelContainer.mainContext }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Core Queries

    var allItems: [MediaItem] {
        let descriptor = FetchDescriptor<MediaItem>(
            sortBy: [SortDescriptor(\.importDate, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var allTags: [String] {
        // Fetch without sorting — we only need the tags field, and allItems adds
        // an unnecessary ORDER BY that the database has to evaluate.
        let descriptor = FetchDescriptor<MediaItem>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        return items.reduce(into: Set<String>()) { $0.formUnion($1.tags) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var allSources: [String] {
        let sources = allItems.compactMap { $0.source }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(Set(sources)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func items(matching predicate: Predicate<MediaItem>? = nil, sortedBy sortOrder: SortOrder = .dateImported, ascending: Bool = false) -> [MediaItem] {
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)

        switch sortOrder {
        case .name:
            descriptor.sortBy = [SortDescriptor(\.originalFilename, order: ascending ? .forward : .reverse)]
        case .dateModified:
            descriptor.sortBy = [SortDescriptor(\.fileModifiedDate, order: ascending ? .forward : .reverse)]
        case .dateImported:
            descriptor.sortBy = [SortDescriptor(\.importDate, order: ascending ? .forward : .reverse)]
        case .fileSize:
            descriptor.sortBy = [SortDescriptor(\.fileSize, order: ascending ? .forward : .reverse)]
        case .duration:
            descriptor.sortBy = [SortDescriptor(\.duration, order: ascending ? .forward : .reverse)]
        }

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Lookup

    func items(inFolder folder: String, includeSubfolders: Bool) -> [MediaItem] {
        allItems.filter { item in
            if includeSubfolders {
                return item.relativePath.hasPrefix(folder)
            } else {
                let itemFolder = (item.relativePath as NSString).deletingLastPathComponent
                return itemFolder == folder
            }
        }
    }

    func item(withHash hash: String) -> MediaItem? {
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func fetchCount() -> Int {
        let descriptor = FetchDescriptor<MediaItem>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Smart Album Queries

    func lastImportItems(since importDate: Date, sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        let threshold = importDate.addingTimeInterval(-2)
        let predicate = #Predicate<MediaItem> { $0.importDate >= threshold }
        return items(matching: predicate, sortedBy: sortOrder, ascending: ascending)
    }

    func importedTodayItems(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<MediaItem> { $0.importDate >= startOfDay }
        return items(matching: predicate, sortedBy: sortOrder, ascending: ascending)
    }

    var unplayableVideoCount: Int {
        allItems.filter { $0.isVideo && $0.hasThumbnailError }.count
    }

    func unplayableVideos(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        items(sortedBy: sortOrder, ascending: ascending)
            .filter { $0.isVideo && $0.hasThumbnailError }
    }

    var decodeErrorVideoCount: Int {
        allItems.filter { $0.isVideo && $0.hasDecodeError }.count
    }

    func decodeErrorVideos(sortedBy sortOrder: SortOrder, ascending: Bool) -> [MediaItem] {
        items(sortedBy: sortOrder, ascending: ascending)
            .filter { $0.isVideo && $0.hasDecodeError }
    }

    func items(in location: StorageLocation) -> [MediaItem] {
        allItems.filter { $0.storageLocation == location }
    }
}
