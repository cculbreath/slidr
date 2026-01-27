import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService

    @State private var sidebarViewModel = SidebarViewModel()
    @State private var gridViewModel = GridViewModel()
    @State private var slideshowViewModel = SlideshowViewModel()
    @State private var showSlideshow = false
    @State private var showInspector = false
    @State private var inspectorItem: MediaItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: sidebarViewModel)
        } detail: {
            MediaGridView(
                viewModel: gridViewModel,
                items: currentItems,
                onStartSlideshow: startSlideshow,
                onSelectItem: { item in
                    inspectorItem = item
                }
            )
        }
        .inspector(isPresented: $showInspector) {
            inspectorContent
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
            showInspector.toggle()
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
        }
    }

    private var currentItems: [MediaItem] {
        switch sidebarViewModel.selectedItem {
        case .allMedia, .none:
            return library.items(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
        case .favorites:
            return library.items(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
                .filter { $0.isFavorite }
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

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if let item = inspectorItem {
            MediaInspectorView(item: item)
        } else if let firstSelectedID = gridViewModel.selectedItems.first,
                  let item = currentItems.first(where: { $0.id == firstSelectedID }) {
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
