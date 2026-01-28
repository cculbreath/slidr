import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct MediaGridView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: GridViewModel
    @Query private var settingsQuery: [AppSettings]

    let items: [MediaItem]
    let onStartSlideshow: ([MediaItem], Int) -> Void
    var onQuickLook: ((MediaItem) -> Void)?

    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [MediaItem] = []
    @State private var containerWidth: CGFloat = 0
    @State private var hoveredItemID: UUID?
    @FocusState private var isFocused: Bool

    private var settings: AppSettings? {
        settingsQuery.first
    }

    private var displayedItems: [MediaItem] {
        viewModel.filteredItems(items)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(
                    title: "No Media",
                    subtitle: "Import images, GIFs, and videos to get started",
                    systemImage: "photo.on.rectangle.angled",
                    action: { importFiles() },
                    actionLabel: "Import Files"
                )
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVGrid(columns: viewModel.gridColumns, spacing: 8) {
                            ForEach(displayedItems) { item in
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
                                .contextMenu {
                                    Button("Show in Finder") {
                                        showInFinder(item)
                                    }

                                    if item.storageLocation == .referenced {
                                        Button("Copy to Library") {
                                            copyToLibrary(item)
                                        }
                                    }

                                    Divider()

                                    Button("Move to Trash", role: .destructive) {
                                        itemsToDelete = [item]
                                        showDeleteConfirmation = true
                                    }
                                }
                            }
                        }
                        .overlayPreferenceValue(HoverCellAnchorKey.self) { anchor in
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
                        .padding()
                    }
                    .animation(.easeInOut(duration: 0.25), value: viewModel.thumbnailSize)
                    .focusable()
                    .focused($isFocused)
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
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    importFiles()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }

            ToolbarItem(placement: .automatic) {
                Picker("Size", selection: $viewModel.thumbnailSize) {
                    ForEach(ThumbnailSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        viewModel.mediaTypeFilter = []
                    } label: {
                        HStack {
                            Text("All")
                            if viewModel.mediaTypeFilter.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(MediaType.allCases, id: \.self) { type in
                        Button {
                            if viewModel.mediaTypeFilter.contains(type) {
                                viewModel.mediaTypeFilter.remove(type)
                            } else {
                                viewModel.mediaTypeFilter.insert(type)
                            }
                        } label: {
                            HStack {
                                Text(type.rawValue.capitalized)
                                if viewModel.mediaTypeFilter.contains(type) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Filter", systemImage: viewModel.mediaTypeFilter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            viewModel.sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if viewModel.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Toggle("Ascending", isOn: $viewModel.sortAscending)
                } label: {
                    Label("Sort", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    toggleGIFAnimation()
                } label: {
                    Label(
                        settings?.animateGIFsInGrid == true ? "GIFs: On" : "GIFs: Off",
                        image: settings?.animateGIFsInGrid == true ? "custom.gifs.pause" : "custom.gifs.play"
                    )
                }
                .help("Toggle GIF animation in grid")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    startSlideshow()
                } label: {
                    Label("Slideshow", systemImage: "play.rectangle.on.rectangle")
                }
                .disabled(items.isEmpty)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
        .onKeyPress(.delete) {
            deleteSelectedItems()
            return .handled
        }
        .onKeyPress(.upArrow) {
            let columns = viewModel.columnCount(for: containerWidth)
            viewModel.moveSelection(direction: .up, in: displayedItems, columns: columns)
            return .handled
        }
        .onKeyPress(.downArrow) {
            let columns = viewModel.columnCount(for: containerWidth)
            viewModel.moveSelection(direction: .down, in: displayedItems, columns: columns)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            let columns = viewModel.columnCount(for: containerWidth)
            viewModel.moveSelection(direction: .left, in: displayedItems, columns: columns)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            let columns = viewModel.columnCount(for: containerWidth)
            viewModel.moveSelection(direction: .right, in: displayedItems, columns: columns)
            return .handled
        }
        .onKeyPress(.space) {
            guard let selectedID = viewModel.selectedItems.first,
                  let item = displayedItems.first(where: { $0.id == selectedID }) else {
                return .ignored
            }
            onQuickLook?(item)
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
            viewModel.selectAll(displayedItems)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deselectAll)) { _ in
            viewModel.clearSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelected)) { _ in
            deleteSelectedItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .increaseThumbnailSize)) { _ in
            viewModel.increaseThumbnailSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: .decreaseThumbnailSize)) { _ in
            viewModel.decreaseThumbnailSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startSlideshow)) { _ in
            startSlideshow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetThumbnailSize)) { _ in
            viewModel.resetThumbnailSize()
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealInFinder)) { _ in
            revealSelectedInFinder()
        }
        .confirmationDialog(
            "Move \(itemsToDelete.count) item\(itemsToDelete.count == 1 ? "" : "s") to Trash?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                performDelete(itemsToDelete)
                itemsToDelete = []
            }
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

    // MARK: - Tap Handling

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

    // MARK: - Delete

    private func deleteSelectedItems() {
        guard !viewModel.selectedItems.isEmpty else { return }

        let selectedItems = displayedItems.filter { viewModel.selectedItems.contains($0.id) }
        guard !selectedItems.isEmpty else { return }

        if settings?.confirmBeforeDelete == true {
            itemsToDelete = selectedItems
            showDeleteConfirmation = true
        } else {
            performDelete(selectedItems)
        }
    }

    private func performDelete(_ itemsToDelete: [MediaItem]) {
        library.delete(itemsToDelete)
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
        Task {
            try? await library.copyToLibrary(item)
        }
    }

    // MARK: - Hover Reveal Overlay

    @ViewBuilder
    private func hoverRevealContent(for item: MediaItem) -> some View {
        let pixelSize = viewModel.thumbnailSize.pixelSize
        let revealedWidth: CGFloat = {
            guard let w = item.width, let h = item.height, h > 0, w > h else { return pixelSize }
            return pixelSize * CGFloat(w) / CGFloat(h)
        }()
        let revealedHeight: CGFloat = {
            guard let w = item.width, let h = item.height, w > 0, h > w else { return pixelSize }
            return pixelSize * CGFloat(h) / CGFloat(w)
        }()

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

    // MARK: - GIF Animation

    private func toggleGIFAnimation() {
        let settings: AppSettings
        if let existing = settingsQuery.first {
            settings = existing
        } else {
            Logger.library.error("AppSettings missing in toggleGIFAnimation — creating fallback defaults")
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            settings = newSettings
        }
        settings.animateGIFsInGrid.toggle()
    }

    // MARK: - Import

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .image,
            .gif,
            .movie,
            .video,
            .mpeg4Movie,
            .quickTimeMovie,
            .avi
        ]

        if panel.runModal() == .OK {
            Task {
                _ = try? await library.importFiles(urls: panel.urls)
            }
        }
    }
}
