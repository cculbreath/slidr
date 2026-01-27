import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MediaGridView: View {
    @Environment(MediaLibrary.self) private var library
    @Bindable var viewModel: GridViewModel
    @Query private var settingsQuery: [AppSettings]

    let items: [MediaItem]
    let onStartSlideshow: ([MediaItem], Int) -> Void
    var onSelectItem: ((MediaItem) -> Void)?

    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [MediaItem] = []

    private var settings: AppSettings? {
        settingsQuery.first
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
                        ForEach(items) { item in
                            MediaThumbnailView(
                                item: item,
                                size: viewModel.thumbnailSize,
                                isSelected: viewModel.isSelected(item),
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
            }
        }
        .toolbar {
            ToolbarItemGroup {
                // Thumbnail size picker
                Picker("Size", selection: $viewModel.thumbnailSize) {
                    ForEach(ThumbnailSize.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Divider()

                // Sort menu
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
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }

                Divider()

                // GIF animation toggle
                Button {
                    toggleGIFAnimation()
                } label: {
                    Label(
                        settings?.animateGIFsInGrid == true ? "GIFs: On" : "GIFs: Off",
                        systemImage: settings?.animateGIFsInGrid == true ? "play.circle.fill" : "play.circle"
                    )
                }
                .help("Toggle GIF animation in grid")

                Divider()

                // Slideshow button
                Button {
                    startSlideshow()
                } label: {
                    Label("Slideshow", systemImage: "play.fill")
                }
                .disabled(items.isEmpty)
            }
        }
        .onKeyPress(.delete) {
            deleteSelectedItems()
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectAll)) { _ in
            viewModel.selectAll(items)
        }
        .onReceive(NotificationCenter.default.publisher(for: .deselectAll)) { _ in
            viewModel.clearSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelected)) { _ in
            deleteSelectedItems()
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
            viewModel.extendSelection(to: item, in: items)
        } else {
            viewModel.select(item)
        }
        onSelectItem?(item)
    }

    private func handleDoubleTap(_ item: MediaItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        onStartSlideshow(items, index)
    }

    private func startSlideshow() {
        let selectedItems: [MediaItem]
        let startIndex: Int

        if viewModel.selectedItems.isEmpty {
            selectedItems = items
            startIndex = 0
        } else {
            selectedItems = items.filter { viewModel.selectedItems.contains($0.id) }
            startIndex = 0
        }

        onStartSlideshow(selectedItems, startIndex)
    }

    // MARK: - Delete

    private func deleteSelectedItems() {
        guard !viewModel.selectedItems.isEmpty else { return }

        let selectedItems = items.filter { viewModel.selectedItems.contains($0.id) }
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
