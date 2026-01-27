import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MediaGridView: View {
    @Environment(MediaLibrary.self) private var library
    @Bindable var viewModel: GridViewModel
    @Query private var settingsQuery: [AppSettings]

    let items: [MediaItem]
    let onStartSlideshow: ([MediaItem], Int) -> Void
    var onQuickLook: ((MediaItem) -> Void)?

    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [MediaItem] = []
    @State private var containerWidth: CGFloat = 0

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
                ScrollView {
                    LazyVGrid(columns: viewModel.gridColumns, spacing: 8) {
                        ForEach(displayedItems) { item in
                            MediaThumbnailView(
                                item: item,
                                size: viewModel.thumbnailSize,
                                isSelected: viewModel.isSelected(item),
                                selectedItemIDs: viewModel.selectedItems,
                                onTap: { handleTap(item) },
                                onDoubleTap: { handleDoubleTap(item) }
                            )
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

                                Button("Delete", role: .destructive) {
                                    itemsToDelete = [item]
                                    showDeleteConfirmation = true
                                }
                            }
                        }
                    }
                    .padding()
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
                    Label("Sort", systemImage: "line.3.horizontal.decrease")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    toggleGIFAnimation()
                } label: {
                    Label(
                        settings?.animateGIFsInGrid == true ? "GIFs: On" : "GIFs: Off",
                        systemImage: settings?.animateGIFsInGrid == true ? "photo.stack.fill" : "photo.stack"
                    )
                }
                .help("Toggle GIF animation in grid")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    startSlideshow()
                } label: {
                    Label("Slideshow", systemImage: "play.fill")
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
            "Delete \(itemsToDelete.count) item\(itemsToDelete.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete(itemsToDelete)
                itemsToDelete = []
            }
            Button("Cancel", role: .cancel) {
                itemsToDelete = []
            }
        } message: {
            if itemsToDelete.count == 1 {
                Text("This will permanently delete \"\(itemsToDelete.first?.originalFilename ?? "")\" from the library.")
            } else {
                Text("This will permanently delete \(itemsToDelete.count) items from the library.")
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
        let selectedItems: [MediaItem]
        let startIndex: Int

        if viewModel.selectedItems.isEmpty {
            selectedItems = displayedItems
            startIndex = 0
        } else {
            selectedItems = displayedItems.filter { viewModel.selectedItems.contains($0.id) }
            startIndex = 0
        }

        onStartSlideshow(selectedItems, startIndex)
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

    // MARK: - GIF Animation

    private func toggleGIFAnimation() {
        guard let settings = settingsQuery.first else { return }
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
