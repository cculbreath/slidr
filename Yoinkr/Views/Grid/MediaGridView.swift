import SwiftUI
import SwiftData

struct MediaGridView: View {
    @Environment(MediaLibrary.self) private var library
    @Bindable var viewModel: GridViewModel

    let items: [MediaItem]
    let onStartSlideshow: ([MediaItem], Int) -> Void

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(
                    title: "No Media",
                    subtitle: "Import images and GIFs to get started",
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
                .frame(width: 200)

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

                // Slideshow button
                Button {
                    startSlideshow()
                } label: {
                    Label("Slideshow", systemImage: "play.fill")
                }
                .disabled(items.isEmpty)
            }
        }
    }

    private func handleTap(_ item: MediaItem) {
        if NSEvent.modifierFlags.contains(.command) {
            viewModel.toggleSelection(item)
        } else if NSEvent.modifierFlags.contains(.shift) {
            viewModel.extendSelection(to: item, in: items)
        } else {
            viewModel.select(item)
        }
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

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .gif]

        if panel.runModal() == .OK {
            Task {
                _ = try? await library.importFiles(urls: panel.urls)
            }
        }
    }
}
