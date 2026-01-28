import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsQuery: [AppSettings]

    @State private var sidebarViewModel = SidebarViewModel()
    @State private var gridViewModel = GridViewModel()
    @State private var slideshowViewModel = SlideshowViewModel()
    @State private var showSlideshow = false
    @State private var externalSlideshowActive = false
    @State private var showInspector = false
    @State private var isDropTargeted = false
    @State private var previewItem: MediaItem?
    @State private var cachedItems: [MediaItem] = []

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(viewModel: sidebarViewModel)
            } detail: {
                if let previewItem {
                    MediaPreviewView(item: previewItem, items: cachedItems, library: library) {
                        self.previewItem = nil
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    MediaGridView(
                        viewModel: gridViewModel,
                        items: cachedItems,
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
            .onChange(of: sidebarViewModel.selectedItem) {
                gridViewModel.clearSelection()
                refreshItems()
            }
            .onChange(of: gridViewModel.sortOrder) { _, newOrder in
                refreshItems()
                settingsQuery.first?.defaultSortOrder = newOrder
            }
            .onChange(of: gridViewModel.sortAscending) { _, newValue in
                refreshItems()
                settingsQuery.first?.defaultSortAscending = newValue
            }
            .onChange(of: library.libraryVersion) { refreshItems() }
            .allowsHitTesting(!showSlideshow)
            .toolbar(showSlideshow ? .hidden : .automatic, for: .windowToolbar)
            .onAppear {
                sidebarViewModel.configure(with: playlistService)
                if sidebarViewModel.selectedItem == nil {
                    sidebarViewModel.selectedItem = .allMedia
                }
                if let settings = settingsQuery.first {
                    gridViewModel.sortOrder = settings.defaultSortOrder
                    gridViewModel.sortAscending = settings.defaultSortAscending
                }
                refreshItems()
                // Background-generate missing scrub thumbnails for videos
                let count = settingsQuery.first?.scrubThumbnailCount ?? 100
                library.backgroundGenerateMissingScrubThumbnails(count: count)
            }

            if showSlideshow {
                SlideshowView(viewModel: slideshowViewModel, onDismiss: dismissSlideshow)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSlideshow)
        .onChange(of: slideshowViewModel.currentIndex) { _, newIndex in
            guard showSlideshow || externalSlideshowActive else { return }
            let active = slideshowViewModel.activeItems
            guard newIndex >= 0, newIndex < active.count else { return }
            gridViewModel.selectedItems = [active[newIndex].id]
        }
    }

    private func refreshItems() {
        cachedItems = fetchItems()
    }

    private func fetchItems() -> [MediaItem] {
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

        let settings = settingsQuery.first
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens.first

        if settings?.useAllMonitors == true,
           screens.count > 1,
           let externalScreen = screens.first(where: { $0 != mainScreen }) {
            // External display mode: slideshow on external, browser stays interactive
            externalSlideshowActive = true
            let appDelegate = NSApplication.shared.delegate as? AppDelegate

            let slideshowContent = SlideshowView(
                viewModel: slideshowViewModel,
                onDismiss: dismissSlideshow
            )
            .environment(library)
            .modelContainer(modelContext.container)

            let showControlPanel = settings?.controlPanelOnSeparateMonitor == true
            appDelegate?.openExternalSlideshow(
                on: externalScreen,
                content: slideshowContent,
                controlContent: showControlPanel ? AnyView(
                    SlideshowControlPanel(viewModel: slideshowViewModel, onClose: dismissSlideshow)
                ) : nil,
                controlScreen: showControlPanel ? mainScreen : nil
            )
        } else {
            // Single monitor: inline slideshow
            showSlideshow = true
        }
    }

    private func dismissSlideshow() {
        slideshowViewModel.stop()

        if externalSlideshowActive {
            externalSlideshowActive = false
            let appDelegate = NSApplication.shared.delegate as? AppDelegate
            appDelegate?.closeAllSlideshowWindows()
        } else {
            showSlideshow = false
        }
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
                  let item = cachedItems.first(where: { $0.id == selectedID }) {
            withAnimation(.easeInOut(duration: 0.25)) {
                previewItem = item
            }
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        if gridViewModel.selectedItems.count > 1 {
            let selectedMediaItems = cachedItems.filter { gridViewModel.selectedItems.contains($0.id) }
            MultiSelectInspectorView(items: selectedMediaItems, library: library, playlistService: playlistService)
        } else if let selectedID = gridViewModel.selectedItems.first,
                  let item = cachedItems.first(where: { $0.id == selectedID }) {
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
