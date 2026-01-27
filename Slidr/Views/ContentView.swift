import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @Query private var settingsQuery: [AppSettings]

    @State private var sidebarViewModel = SidebarViewModel()
    @State private var gridViewModel = GridViewModel()
    @State private var slideshowViewModel = SlideshowViewModel()
    @State private var showSlideshow = false
    @State private var showInspector = false
    @State private var isDropTargeted = false
    @State private var previewItem: MediaItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: sidebarViewModel)
        } detail: {
            if let previewItem {
                MediaPreviewView(item: previewItem, items: currentItems, library: library) {
                    self.previewItem = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                MediaGridView(
                    viewModel: gridViewModel,
                    items: currentItems,
                    onStartSlideshow: startSlideshow,
                    onQuickLook: { item in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            previewItem = item
                        }
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: previewItem != nil)
        .searchable(text: $gridViewModel.searchText, prompt: "Search media")
        .inspector(isPresented: $showInspector) {
            inspectorContent
        }
        .dropZone(isTargeted: $isDropTargeted) { urls in
            Task {
                _ = try? await library.importFiles(urls: urls)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .ignoresSafeArea()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
            showInspector.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importFiles)) { _ in
            importFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickLook)) { _ in
            togglePreview()
        }
        .sheet(isPresented: $showSlideshow) {
            slideshowViewModel.stop()
        } content: {
            SlideshowView(viewModel: slideshowViewModel)
                .frame(minWidth: 800, minHeight: 600)
        }
        .onChange(of: sidebarViewModel.selectedItem) {
            gridViewModel.clearSelection()
        }
        .onAppear {
            sidebarViewModel.configure(with: playlistService)
            if sidebarViewModel.selectedItem == nil {
                sidebarViewModel.selectedItem = .allMedia
            }
            // Background-generate missing scrub thumbnails for videos
            let count = settingsQuery.first?.scrubThumbnailCount ?? 100
            library.backgroundGenerateMissingScrubThumbnails(count: count)
        }
    }

    private var currentItems: [MediaItem] {
        _ = library.libraryVersion
        switch sidebarViewModel.selectedItem {
        case .allMedia, .none:
            return library.items(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
        case .favorites:
            return library.items(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
                .filter { $0.isFavorite }
        case .lastImport:
            return library.lastImportItems(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
        case .importedToday:
            return library.importedTodayItems(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
        case .playlist(let id):
            if let playlist = playlistService.playlist(withID: id) {
                return playlistService.items(for: playlist)
            }
            return []
        }
    }

    private func startSlideshow(items: [MediaItem], startIndex: Int) {
        slideshowViewModel.start(with: items, startingAt: startIndex)
        showSlideshow = true
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [
            .image, .gif, .movie, .video, .mpeg4Movie, .quickTimeMovie
        ]

        if panel.runModal() == .OK {
            Task {
                _ = try? await library.importFiles(urls: panel.urls)
            }
        }
    }

    private func togglePreview() {
        if previewItem != nil {
            withAnimation(.easeInOut(duration: 0.25)) {
                previewItem = nil
            }
        } else if let selectedID = gridViewModel.selectedItems.first,
                  let item = currentItems.first(where: { $0.id == selectedID }) {
            withAnimation(.easeInOut(duration: 0.25)) {
                previewItem = item
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if gridViewModel.selectedItems.count > 1 {
            let selectedMediaItems = currentItems.filter { gridViewModel.selectedItems.contains($0.id) }
            MultiSelectInspectorView(items: selectedMediaItems, library: library, playlistService: playlistService)
        } else if let selectedID = gridViewModel.selectedItems.first,
                  let item = currentItems.first(where: { $0.id == selectedID }) {
            MediaInspectorView(item: item)
        } else {
            VStack {
                Image(systemName: "sidebar.right")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text("Select an item to inspect")
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 280)
        }
    }
}
