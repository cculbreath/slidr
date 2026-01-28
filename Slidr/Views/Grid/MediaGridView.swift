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
    var activePlaylist: Playlist?

    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [MediaItem] = []
    @State private var containerWidth: CGFloat = 0
    @State private var hoveredItemID: UUID?
    @FocusState private var isFocused: Bool

    private var settings: AppSettings? { settingsQuery.first }
    private var displayedItems: [MediaItem] { viewModel.filteredItems(items) }

    var body: some View {
        VStack(spacing: 0) {
            externalDriveBanner
            gridContent
        }
        .toolbar {
            GridToolbarContent(
                viewModel: viewModel,
                settings: settings,
                itemsEmpty: items.isEmpty,
                onImport: importFiles,
                onToggleGIFAnimation: toggleGIFAnimation,
                onToggleHoverScrub: toggleHoverScrub,
                onToggleCaptions: toggleGridCaptions,
                onToggleFilenames: toggleGridFilenames,
                onStartSlideshow: startSlideshow
            )
        }
        .gridKeyboardHandling(
            viewModel: viewModel,
            displayedItems: displayedItems,
            containerWidth: containerWidth,
            onDelete: deleteSelectedItems,
            onQuickLook: quickLookSelected,
            onStartSlideshow: startSlideshow,
            onRevealInFinder: revealSelectedInFinder,
            onToggleFilenames: toggleGridFilenames,
            onToggleCaptions: toggleGridCaptions,
            onSelectAll: { viewModel.selectAll(displayedItems) },
            onDeselectAll: { viewModel.clearSelection() },
            onMoveSelection: { direction in
                let columns = viewModel.columnCount(for: containerWidth)
                viewModel.moveSelection(direction: direction, in: displayedItems, columns: columns)
            }
        )
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
    private var gridContent: some View {
        if items.isEmpty {
            EmptyStateView(
                title: "No Media",
                subtitle: "Import images, GIFs, and videos to get started",
                systemImage: "photo.on.rectangle.angled",
                action: importFiles,
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

    // MARK: - Import

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .gif, .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]

        if panel.runModal() == .OK {
            Task { _ = try? await library.importFiles(urls: panel.urls) }
        }
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
