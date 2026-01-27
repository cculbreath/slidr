import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(MediaLibrary.self) private var library

    @State private var sidebarSelection: SidebarItem? = .allMedia
    @State private var gridViewModel = GridViewModel()
    @State private var slideshowViewModel = SlideshowViewModel()
    @State private var showSlideshow = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } detail: {
            MediaGridView(
                viewModel: gridViewModel,
                items: currentItems,
                onStartSlideshow: startSlideshow
            )
        }
        .sheet(isPresented: $showSlideshow) {
            slideshowViewModel.stop()
        } content: {
            SlideshowView(viewModel: slideshowViewModel)
                .frame(minWidth: 800, minHeight: 600)
        }
        .onAppear {
            // Ensure we have a selection
            if sidebarSelection == nil {
                sidebarSelection = .allMedia
            }
        }
    }

    private var currentItems: [MediaItem] {
        switch sidebarSelection {
        case .allMedia, .none:
            return library.items(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
        case .playlist:
            // Playlist support in Phase 3
            return []
        }
    }

    private func startSlideshow(items: [MediaItem], startIndex: Int) {
        slideshowViewModel.start(with: items, startingAt: startIndex)
        showSlideshow = true
    }
}
