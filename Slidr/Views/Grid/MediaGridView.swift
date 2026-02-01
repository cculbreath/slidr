import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct MediaGridView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: GridViewModel
    @Query private var settingsQuery: [AppSettings]

    let items: [MediaItem]
    let onStartSlideshow: ([MediaItem], Int) -> Void
    var onQuickLook: ((MediaItem) -> Void)?
    var onImportFiles: (() -> Void)?
    var onToggleInspector: (() -> Void)?
    var activePlaylist: Playlist?
    var isDecodeErrorsView: Bool = false

    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [MediaItem] = []
    @State private var containerWidth: CGFloat = 0
    @State private var hoveredItemID: UUID?
    @State private var isRetryingThumbnails = false
    @State private var retryProgress: (current: Int, total: Int)?
    @State private var retryResult: Int?
    @State private var showTrashAllConfirmation = false
    @State private var showAdvancedFilter = false
    @FocusState private var isFocused: Bool

    let toolbarCoordinator: GridToolbarCoordinator

    private var settings: AppSettings? { settingsQuery.first }
    private var displayedItems: [MediaItem] { viewModel.filteredItems(items) }
    private var allTags: [String] {
        Array(Set(items.flatMap(\.tags))).sorted()
    }
    private var hasActiveFilters: Bool {
        !viewModel.searchText.isEmpty
        || !viewModel.mediaTypeFilter.isEmpty
        || !viewModel.productionTypeFilter.isEmpty
        || !viewModel.tagFilter.isEmpty
        || (viewModel.ratingFilterEnabled && !viewModel.ratingFilter.isEmpty)
        || viewModel.subtitleFilter
        || viewModel.captionFilter
        || viewModel.advancedFilter != nil
    }

    var body: some View {
        gridWithToolbar
            // Expose focused values for menu commands
            .focusedSceneValue(\.selectAll, { viewModel.selectAll(displayedItems) })
            .focusedSceneValue(\.deselectAll, { viewModel.clearSelection() })
            .focusedSceneValue(\.deleteSelected, { deleteSelectedItems() })
            .focusedSceneValue(\.startSlideshow, { startSlideshow() })
            .focusedSceneValue(\.revealInFinder, { revealSelectedInFinder() })
            .focusedSceneValue(\.increaseThumbnailSize, { viewModel.increaseThumbnailSize() })
            .focusedSceneValue(\.decreaseThumbnailSize, { viewModel.decreaseThumbnailSize() })
            .focusedSceneValue(\.resetThumbnailSize, { viewModel.resetThumbnailSize() })
            .focusedSceneValue(\.showAdvancedFilter, { showAdvancedFilter = true })
            .focusedSceneValue(\.clearAllFilters, { viewModel.clearAllFilters() })
            .sheet(isPresented: $showAdvancedFilter) {
                AdvancedFilterSheet(viewModel: viewModel)
            }
            .alert(
                "Move to Trash?",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Move to Trash", role: .destructive) {
                    performDelete(itemsToDelete)
                    itemsToDelete = []
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    itemsToDelete = []
                }
            } message: {
                if itemsToDelete.count == 1 {
                    Text("\"\(itemsToDelete.first?.originalFilename ?? "")\" will be moved to the Trash.")
                } else {
                    Text("\(itemsToDelete.count) items will be moved to the Trash.")
                }
            }
            .alert(
                "Move All to Trash?",
                isPresented: $showTrashAllConfirmation
            ) {
                Button("Move to Trash", role: .destructive) {
                    performDelete(items)
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(items.count) video\(items.count == 1 ? "" : "s") with decode errors will be moved to the Trash.")
            }
    }

    private var gridWithToolbar: some View {
        VStack(spacing: 0) {
            externalDriveBanner
            decodeErrorBanner
            advancedFilterBanner
            gridContent
            if !items.isEmpty {
                itemCountBar
            }
        }
        .modifier(WindowToolbarModifier(coordinator: toolbarCoordinator))
        .gridKeyboardHandling(
            onDelete: deleteSelectedItems,
            onQuickLook: quickLookSelected,
            onMoveSelection: { direction in
                let columns = viewModel.columnCount(for: containerWidth)
                viewModel.moveSelection(direction: direction, in: displayedItems, columns: columns)
            }
        )
        .onAppear { configureToolbar() }
        .onChange(of: items.isEmpty) { _, empty in
            toolbarCoordinator.itemsEmpty = empty
        }
        .onChange(of: allTags) { _, tags in
            toolbarCoordinator.allTags = tags
        }
    }

    private func configureToolbar() {
        toolbarCoordinator.viewModel = viewModel
        toolbarCoordinator.settings = settings
        toolbarCoordinator.itemsEmpty = items.isEmpty
        toolbarCoordinator.allTags = allTags
        toolbarCoordinator.onStartSlideshow = startSlideshow
        toolbarCoordinator.onImport = { [onImportFiles] in onImportFiles?() }
        toolbarCoordinator.onToggleGIFAnimation = toggleGIFAnimation
        toolbarCoordinator.onToggleHoverScrub = toggleHoverScrub
        toolbarCoordinator.onToggleCaptions = toggleGridCaptions
        toolbarCoordinator.onToggleFilenames = toggleGridFilenames
        toolbarCoordinator.onToggleInspector = { [onToggleInspector] in onToggleInspector?() }
        toolbarCoordinator.onShowAdvancedFilter = { self.showAdvancedFilter = true }
        toolbarCoordinator.startObserving()
    }

    // MARK: - View Components

    @ViewBuilder
    private var externalDriveBanner: some View {
        if !library.isExternalDriveConnected && library.externalItemCount > 0 {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.xmark")
                    .foregroundStyle(.orange)
                Text("External drive not connected \u{2014} \(library.externalItemCount) item\(library.externalItemCount == 1 ? " is" : "s are") unavailable")
                    .font(.callout)
                Spacer()
                Button("Locate...") {
                    library.locateExternalLibrary()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.1))
        }
    }

    @ViewBuilder
    private var decodeErrorBanner: some View {
        if isDecodeErrorsView && !items.isEmpty {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text("\(items.count) video\(items.count == 1 ? "" : "s") failed thumbnail decoding")
                        .font(.callout)
                    Spacer()
                    Button("Retry Thumbnails") {
                        retryThumbnails()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRetryingThumbnails)

                    Button("Move All to Trash", role: .destructive) {
                        showTrashAllConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRetryingThumbnails)
                }

                if isRetryingThumbnails, let progress = retryProgress {
                    ProgressView("Processing \(progress.current) of \(progress.total)...",
                                 value: Double(progress.current),
                                 total: Double(max(progress.total, 1)))
                        .font(.caption)
                }

                if let recovered = retryResult {
                    Text(recovered > 0
                         ? "Recovered \(recovered) video\(recovered == 1 ? "" : "s"). Remaining items still have decode errors."
                         : "No videos recovered \u{2014} all items still have decode errors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.yellow.opacity(0.1))
        }
    }

    @ViewBuilder
    private var advancedFilterBanner: some View {
        if let filter = viewModel.advancedFilter, !filter.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(.blue)
                Text("Advanced filter active \u{2014} \(filter.rules.count) rule\(filter.rules.count == 1 ? "" : "s")")
                    .font(.callout)
                Spacer()
                Button("Clear") {
                    viewModel.clearAdvancedFilter()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.1))
        }
    }

    private var itemCountBar: some View {
        HStack {
            Spacer()
            if hasActiveFilters {
                Text("\(displayedItems.count) of \(items.count) items")
            } else {
                Text("\(items.count) items")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private var gridContent: some View {
        if items.isEmpty {
            EmptyStateView(
                title: "No Media",
                subtitle: "Import images, GIFs, and videos to get started",
                systemImage: "photo.on.rectangle.angled",
                action: { onImportFiles?() },
                actionLabel: "Import Files"
            )
        } else {
            gridScrollView
        }
    }

    private var gridScrollView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                gridLazyVGrid
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.thumbnailSize)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear {
                isFocused = true
                if let selectedID = viewModel.selectedItems.first {
                    scrollProxy.scrollTo(selectedID, anchor: .center)
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { containerWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            containerWidth = newWidth
                        }
                }
            }
        }
    }

    private var gridLazyVGrid: some View {
        LazyVGrid(columns: viewModel.gridColumns, spacing: 8) {
            ForEach(displayedItems) { item in
                gridThumbnail(for: item)
            }
        }
        .overlayPreferenceValue(HoverCellAnchorKey.self) { anchor in
            hoverOverlay(anchor: anchor)
        }
        .padding()
    }

    @ViewBuilder
    private func gridThumbnail(for item: MediaItem) -> some View {
        MediaThumbnailView(
            item: item,
            size: viewModel.thumbnailSize,
            isSelected: viewModel.isSelected(item),
            selectedItemIDs: viewModel.selectedItems,
            hoveredItemID: $hoveredItemID,
            onTap: { handleTap(item) },
            onDoubleTap: { handleDoubleTap(item) }
        )
        .id(item.id)
        .contextMenu { thumbnailContextMenu(for: item) }
    }

    @ViewBuilder
    private func thumbnailContextMenu(for item: MediaItem) -> some View {
        Button("Show in Finder") { showInFinder(item) }

        if item.storageLocation == .referenced {
            Button("Copy to Library") { copyToLibrary(item) }
        }

        if let playlist = activePlaylist, playlist.isManualPlaylist {
            Button("Remove from Playlist") { removeFromPlaylist(item, playlist: playlist) }
        }

        Divider()

        Button("Move to Trash", role: .destructive) {
            itemsToDelete = [item]
            showDeleteConfirmation = true
        }
    }

    @ViewBuilder
    private func hoverOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            if let anchor,
               let id = hoveredItemID,
               let item = displayedItems.first(where: { $0.id == id }),
               !item.isVideo {
                let frame = proxy[anchor]
                hoverRevealContent(for: item)
                    .id(id)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: hoveredItemID)
    }

    @ViewBuilder
    private func hoverRevealContent(for item: MediaItem) -> some View {
        let pixelSize = viewModel.thumbnailSize.pixelSize
        let revealedWidth = item.aspectWidth(for: pixelSize)
        let revealedHeight = item.aspectHeight(for: pixelSize)

        Group {
            if item.isAnimated {
                GIFFrameView(url: library.absoluteURL(for: item))
            } else {
                AsyncThumbnailImage(item: item, size: viewModel.thumbnailSize)
            }
        }
        .frame(width: revealedWidth, height: revealedHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(viewModel.isSelected(item) ? Color.accentColor : Color.clear, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.3), radius: 8)
        .scaleEffect(1.15)
    }

    // MARK: - Selection & Navigation

    private func handleTap(_ item: MediaItem) {
        if NSEvent.modifierFlags.contains(.command) {
            viewModel.toggleSelection(item)
        } else if NSEvent.modifierFlags.contains(.shift) {
            viewModel.extendSelection(to: item, in: displayedItems)
        } else {
            viewModel.select(item)
        }
    }

    private func handleDoubleTap(_ item: MediaItem) {
        guard let index = displayedItems.firstIndex(where: { $0.id == item.id }) else { return }
        onStartSlideshow(displayedItems, index)
    }

    private func startSlideshow() {
        let startIndex: Int
        if let selectedID = viewModel.selectedItems.first,
           let idx = displayedItems.firstIndex(where: { $0.id == selectedID }) {
            startIndex = idx
        } else {
            startIndex = 0
        }
        onStartSlideshow(displayedItems, startIndex)
    }

    private func quickLookSelected() {
        guard let selectedID = viewModel.selectedItems.first,
              let item = displayedItems.first(where: { $0.id == selectedID }) else { return }
        onQuickLook?(item)
    }

    // MARK: - Delete

    private func deleteSelectedItems() {
        guard !viewModel.selectedItems.isEmpty else { return }
        let selectedItems = displayedItems.filter { viewModel.selectedItems.contains($0.id) }
        guard !selectedItems.isEmpty else { return }

        // In a manual playlist: remove from playlist instead of deleting
        if let playlist = activePlaylist, playlist.isManualPlaylist {
            for item in selectedItems {
                playlistService.removeItem(item, from: playlist)
            }
            viewModel.clearSelection()
            return
        }

        // In All Media or smart playlist: move to trash with confirmation
        if settings?.confirmBeforeDelete == true {
            itemsToDelete = selectedItems
            showDeleteConfirmation = true
        } else {
            performDelete(selectedItems)
        }
    }

    private func performDelete(_ items: [MediaItem]) {
        library.delete(items)
        viewModel.clearSelection()
    }

    // MARK: - Decode Error Actions

    private func retryThumbnails() {
        isRetryingThumbnails = true
        retryResult = nil
        retryProgress = (0, items.count)

        Task {
            let recovered = await library.retryDecodeErrorThumbnails(for: items) { current, total in
                retryProgress = (current, total)
            }
            retryResult = recovered
            isRetryingThumbnails = false
        }
    }

    // MARK: - Context Menu Actions

    private func revealSelectedInFinder() {
        guard let selectedID = viewModel.selectedItems.first,
              let item = displayedItems.first(where: { $0.id == selectedID }) else { return }
        showInFinder(item)
    }

    private func showInFinder(_ item: MediaItem) {
        let url = library.absoluteURL(for: item)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func copyToLibrary(_ item: MediaItem) {
        Task { try? await library.copyToLibrary(item) }
    }

    private func removeFromPlaylist(_ item: MediaItem, playlist: Playlist) {
        playlistService.removeItem(item, from: playlist)
    }

    // MARK: - Settings Toggles

    private func toggleGIFAnimation() {
        withSettings { $0.animateGIFsInGrid.toggle() }
    }

    private func toggleGridFilenames() {
        withSettings { $0.gridShowFilenames.toggle() }
    }

    private func toggleGridCaptions() {
        withSettings { $0.gridShowCaptions.toggle() }
    }

    private func toggleHoverScrub() {
        withSettings { $0.gridVideoHoverScrub.toggle() }
    }

    private func withSettings(_ action: (AppSettings) -> Void) {
        let settings: AppSettings
        if let existing = settingsQuery.first {
            settings = existing
        } else {
            Logger.library.error("AppSettings missing — creating fallback defaults")
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            settings = newSettings
        }
        action(settings)
    }

}

// MARK: - MediaItem Helpers

private extension MediaItem {
    func aspectWidth(for baseSize: CGFloat) -> CGFloat {
        guard let w = width, let h = height, h > 0, w > h else { return baseSize }
        return baseSize * CGFloat(w) / CGFloat(h)
    }

    func aspectHeight(for baseSize: CGFloat) -> CGFloat {
        guard let w = width, let h = height, w > 0, h > w else { return baseSize }
        return baseSize * CGFloat(h) / CGFloat(w)
    }
}
