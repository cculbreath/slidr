import SwiftUI
import AppKit

struct MediaListView: View {
    @Bindable var viewModel: GridViewModel
    let items: [MediaItem]
    let onStartSlideshow: ([MediaItem], Int, Double?, Bool) -> Void
    var onQuickLook: ((MediaItem) -> Void)?
    var activePlaylist: Playlist?

    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @SceneStorage("listColumnCustomization") private var columnCustomization: TableColumnCustomization<MediaItem>
    @State private var sortOrder: [KeyPathComparator<MediaItem>] = [
        KeyPathComparator(\MediaItem.importDate, order: .reverse)
    ]

    /// The Table's data. Held in @State and recomputed only when inputs actually
    /// change (see the recompute triggers in `body`), rather than re-sorting
    /// inline on every render. This keeps the array identity stable across the
    /// re-renders the Table fires for selection/hover, so we don't redo the
    /// sort dozens of times per interaction.
    @State private var sortedItems: [MediaItem] = []

    private var displayedItems: [MediaItem] { sortedItems }

    /// Cheap per-render fingerprint of the *filtered* set (ids only). When it
    /// changes — filters, search, or the incoming items changed — we resort.
    /// Plain re-renders (selection, hover) leave it untouched, so no resort.
    private var filteredItemIDs: [UUID] {
        viewModel.filteredItems(items).map(\.id)
    }

    private func recomputeSortedItems() {
        sortedItems = Self.sorted(viewModel.filteredItems(items), by: sortOrder)
    }

    /// Pairs an item with a precomputed sort key so the key is evaluated once
    /// per item instead of on every comparison.
    private struct KeyedItem {
        let key: String
        let item: MediaItem
    }

    /// Sorts using `sortOrder`. The Title column sorts by `displayName`, an
    /// expensive computed property (string scans + a regex match). Feeding it
    /// straight to `sorted(using:)` evaluates the key O(N log N) times; we use a
    /// Schwartzian transform instead — compute `displayName` once per item, then
    /// sort by the cached key with identical comparator semantics. Cheap
    /// stored-property keys take the direct path.
    private static func sorted(_ items: [MediaItem], by order: [KeyPathComparator<MediaItem>]) -> [MediaItem] {
        guard let primary = order.first,
              primary.keyPath == \MediaItem.displayName else {
            return items.sorted(using: order)
        }
        return items
            .map { KeyedItem(key: $0.displayName, item: $0) }
            .sorted(using: KeyPathComparator(\KeyedItem.key, order: primary.order))
            .map(\.item)
    }

    var body: some View {
        Table(displayedItems, selection: $viewModel.selectedItems, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            primaryColumns
            metadataColumns
            statusColumns
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            contextMenuContent(for: selectedIDs)
        } primaryAction: { selectedIDs in
            guard let firstID = selectedIDs.first,
                  let index = displayedItems.firstIndex(where: { $0.id == firstID }) else { return }
            onStartSlideshow(displayedItems, index, nil, false)
        }
        .focusedSceneValue(\.listColumnCustomization, $columnCustomization)
        .background(TableRowHeightConfigurator(rowHeight: 36))
        .onAppear { recomputeSortedItems() }
        .onChange(of: sortOrder) { recomputeSortedItems() }
        .onChange(of: filteredItemIDs) { recomputeSortedItems() }
    }

    // MARK: - Column Builders

    @TableColumnBuilder<MediaItem, KeyPathComparator<MediaItem>>
    private var primaryColumns: some TableColumnContent<MediaItem, KeyPathComparator<MediaItem>> {
        TableColumn("Title", value: \MediaItem.displayName) { (item: MediaItem) in
            HStack(spacing: 8) {
                ListThumbnail(item: item, library: library)
                Text(item.displayName)
            }
        }
        .customizationID(ListColumnID.title.rawValue)

        TableColumn("Filename", value: \MediaItem.originalFilename) { (item: MediaItem) in
            Text(item.originalFilename)
        }
        .customizationID(ListColumnID.filename.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Media Type", value: \MediaItem.mediaTypeSortKey) { (item: MediaItem) in
            Text(item.mediaType.rawValue.capitalized)
        }
        .customizationID(ListColumnID.mediaType.rawValue)

        TableColumn("Tags", value: \MediaItem.tagsSortKey) { (item: MediaItem) in
            Text(item.tags.joined(separator: ", "))
                .lineLimit(1)
        }
        .customizationID(ListColumnID.tags.rawValue)

        TableColumn("Caption", value: \MediaItem.captionSortKey) { (item: MediaItem) in
            Text(item.caption ?? "")
                .lineLimit(1)
        }
        .customizationID(ListColumnID.caption.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Transcript", value: \MediaItem.hasTranscriptSortKey) { (item: MediaItem) in
            if item.hasTranscript {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .width(ideal: 70)
        .customizationID(ListColumnID.hasTranscript.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Summary", value: \MediaItem.summarySortKey) { (item: MediaItem) in
            Text(item.summary ?? "")
                .lineLimit(1)
        }
        .customizationID(ListColumnID.summary.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Duration", value: \MediaItem.durationSortKey) { (item: MediaItem) in
            Text(item.formattedDuration ?? "")
        }
        .width(ideal: 60)
        .customizationID(ListColumnID.duration.rawValue)

        TableColumn("File Size", value: \MediaItem.fileSize) { (item: MediaItem) in
            Text(formattedFileSize(item.fileSize))
        }
        .width(ideal: 80)
        .customizationID(ListColumnID.fileSize.rawValue)
    }

    @TableColumnBuilder<MediaItem, KeyPathComparator<MediaItem>>
    private var metadataColumns: some TableColumnContent<MediaItem, KeyPathComparator<MediaItem>> {
        TableColumn("Date Imported", value: \MediaItem.importDate) { (item: MediaItem) in
            Text(item.importDate, style: .date)
        }
        .customizationID(ListColumnID.dateImported.rawValue)

        TableColumn("Date Modified", value: \MediaItem.fileModifiedDate) { (item: MediaItem) in
            Text(item.fileModifiedDate, style: .date)
        }
        .customizationID(ListColumnID.dateModified.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Rating", value: \MediaItem.effectiveRating) { (item: MediaItem) in
            if let rating = item.rating, rating > 0 {
                Text(String(repeating: "\u{2605}", count: rating))
                    .foregroundStyle(.orange)
            }
        }
        .width(ideal: 80)
        .customizationID(ListColumnID.rating.rawValue)

        TableColumn("Production", value: \MediaItem.productionSortKey) { (item: MediaItem) in
            if let production = item.production {
                Label(production.displayName, systemImage: production.iconName)
            }
        }
        .customizationID(ListColumnID.production.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Source", value: \MediaItem.sourceSortKey) { (item: MediaItem) in
            Text(item.source ?? "")
                .lineLimit(1)
        }
        .customizationID(ListColumnID.source.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Dimensions", value: \MediaItem.dimensionsSortKey) { (item: MediaItem) in
            if let w = item.width, let h = item.height {
                Text("\(w) \u{00D7} \(h)")
            }
        }
        .width(ideal: 90)
        .customizationID(ListColumnID.dimensions.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Frame Rate", value: \MediaItem.frameRateSortKey) { (item: MediaItem) in
            if let fps = item.frameRate {
                Text(String(format: "%.1f fps", fps))
            }
        }
        .width(ideal: 80)
        .customizationID(ListColumnID.frameRate.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Audio", value: \MediaItem.hasAudioSortKey) { (item: MediaItem) in
            if let hasAudio = item.hasAudio {
                Image(systemName: hasAudio ? "speaker.wave.2" : "speaker.slash")
                    .foregroundStyle(.secondary)
            }
        }
        .width(ideal: 50)
        .customizationID(ListColumnID.hasAudio.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Frames", value: \MediaItem.frameCountSortKey) { (item: MediaItem) in
            if let count = item.frameCount {
                Text("\(count)")
            }
        }
        .width(ideal: 60)
        .customizationID(ListColumnID.frameCount.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Fav", value: \MediaItem.isFavoriteSortKey) { (item: MediaItem) in
            if item.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }
        }
        .width(ideal: 40)
        .customizationID(ListColumnID.favorite.rawValue)
        .defaultVisibility(.hidden)
    }

    @TableColumnBuilder<MediaItem, KeyPathComparator<MediaItem>>
    private var statusColumns: some TableColumnContent<MediaItem, KeyPathComparator<MediaItem>> {
        TableColumn("Storage", value: \MediaItem.storageLocationSortKey) { (item: MediaItem) in
            Label(item.storageLocation.displayName, systemImage: item.storageLocation.icon)
        }
        .customizationID(ListColumnID.storageLocation.rawValue)
        .defaultVisibility(.hidden)

        TableColumn("Status", value: \MediaItem.statusSortKey) { (item: MediaItem) in
            Text(item.status.rawValue.capitalized)
        }
        .width(ideal: 70)
        .customizationID(ListColumnID.status.rawValue)
        .defaultVisibility(.hidden)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuContent(for selectedIDs: Set<UUID>) -> some View {
        if let firstID = selectedIDs.first,
           let item = displayedItems.first(where: { $0.id == firstID }) {
            Button("Show in Finder") { showInFinder(item) }

            if item.storageLocation == .referenced {
                Button("Copy to Library") { copyToLibrary(item) }
            }

            if let playlist = activePlaylist, playlist.isManualPlaylist {
                Button("Remove from Playlist") {
                    for id in selectedIDs {
                        if let item = displayedItems.first(where: { $0.id == id }) {
                            playlistService.removeItem(item, from: playlist)
                        }
                    }
                }
            }

            Divider()

            Button("Move to Trash", role: .destructive) {
                let items = displayedItems.filter { selectedIDs.contains($0.id) }
                library.delete(items)
                viewModel.clearSelection()
            }
        }
    }

    // MARK: - Actions

    private func showInFinder(_ item: MediaItem) {
        let url = library.absoluteURL(for: item)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func copyToLibrary(_ item: MediaItem) {
        Task { try? await library.copyToLibrary(item) }
    }

    // MARK: - Formatting

    /// Shared formatter — allocating a ByteCountFormatter per cell showed up as a
    /// real cost while the Table builds row views.
    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func formattedFileSize(_ bytes: Int64) -> String {
        Self.fileSizeFormatter.string(fromByteCount: bytes)
    }
}

// MARK: - List Thumbnail

/// Lightweight thumbnail for table rows that takes library explicitly
/// instead of using @Environment, which crashes during Table column resize.
private struct ListThumbnail: View {
    let item: MediaItem
    let library: MediaLibrary
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: item.id) {
            image = try? await library.thumbnail(for: item, size: .small)
        }
    }
}

// MARK: - Fixed Row Height

/// Pins the Table's backing NSTableView to a fixed row height and disables
/// automatic row-height measurement.
///
/// SwiftUI's macOS `Table` defaults to automatic row heights. To measure a row's
/// height it builds that row's entire multi-column view — so a re-sort, which
/// reorders most rows, forces NSTableView to rebuild thousands of full row views
/// synchronously on the main thread. A process sample of the freeze showed exactly
/// this: `_doAutomaticRowHeightsForInsertedAndVisibleRows` → `outlineView(_:viewFor:item:)`
/// for the whole reordered set. Fixed heights skip measurement entirely — only the
/// handful of visible rows are ever built.
private struct TableRowHeightConfigurator: NSViewRepresentable {
    let rowHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let target = rowHeight
        // Defer one cycle so the Table's NSTableView exists in the hierarchy.
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            let table = coordinator.table ?? Self.enclosingTableView(near: nsView)
            coordinator.table = table
            guard let table else { return }
            if table.usesAutomaticRowHeights || abs(table.rowHeight - target) > 0.5 {
                table.usesAutomaticRowHeights = false
                table.rowHeight = target
            }
        }
    }

    /// Walks up to the nearest ancestor whose subtree contains an NSTableView,
    /// which scopes the search to this Table's container rather than, say, the
    /// sidebar's list elsewhere in the window.
    private static func enclosingTableView(near view: NSView) -> NSTableView? {
        var ancestor = view.superview
        while let current = ancestor {
            if let table = firstTableView(in: current) { return table }
            ancestor = current.superview
        }
        return nil
    }

    private static func firstTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for subview in view.subviews {
            if let table = firstTableView(in: subview) { return table }
        }
        return nil
    }

    final class Coordinator {
        weak var table: NSTableView?
    }
}
