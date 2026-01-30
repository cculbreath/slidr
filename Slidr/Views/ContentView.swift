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
    @State private var subtitleImportAlert: String?

    // Local state for menu bindings (avoids SwiftData infinite loop)
    @State private var importDestination: StorageLocation = .local
    @State private var gridShowFilenames: Bool = false
    @State private var gridShowCaptions: Bool = true
    @State private var animateGIFs: Bool = false
    @State private var showSubtitles: Bool = false
    @State private var subtitlePosition: CaptionPosition = .bottom
    @State private var subtitleFontSize: Double = 16.0
    @State private var subtitleOpacity: Double = 0.7

    var body: some View {
        ZStack {
            mainContent

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
        .progressOverlay(
            isPresented: library.importProgress != nil,
            title: "Importing",
            subtitle: importProgressSubtitle,
            progress: library.importProgress?.overallProgress,
            onCancel: { library.cancelImport() }
        )
        .alert("Subtitle Import", isPresented: Binding(
            get: { subtitleImportAlert != nil },
            set: { if !$0 { subtitleImportAlert = nil } }
        )) {
            Button("OK") { subtitleImportAlert = nil }
        } message: {
            Text(subtitleImportAlert ?? "")
        }
    }

    private var importProgressSubtitle: String? {
        guard let progress = library.importProgress else { return nil }
        return "\(progress.currentItem + 1) of \(progress.totalItems): \(progress.currentFilename)"
    }

    private var mainContent: some View {
        navigationViewWithFocusedValues
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
            .onChange(of: settingsQuery.first?.externalDrivePath) { _, newPath in
                library.configureExternalDrive(path: newPath)
            }
            .onChange(of: library.libraryVersion) { refreshItems() }
            .onChange(of: playlistService.playlistChangeGeneration) { refreshItems() }
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
                    gridViewModel.mediaTypeFilter = settings.gridMediaTypeFilter
                    // Initialize menu state from settings
                    importDestination = settings.defaultImportLocation
                    gridShowFilenames = settings.gridShowFilenames
                    gridShowCaptions = settings.gridShowCaptions
                    animateGIFs = settings.animateGIFsInGrid
                    showSubtitles = settings.showSubtitles
                    subtitlePosition = settings.subtitlePosition
                    subtitleFontSize = settings.subtitleFontSize
                    subtitleOpacity = settings.subtitleOpacity
                }
                refreshItems()
                let count = settingsQuery.first?.scrubThumbnailCount ?? 100
                library.backgroundGenerateMissingScrubThumbnails(count: count)
            }
            .onChange(of: gridViewModel.mediaTypeFilter) { _, newFilter in
                refreshItems()
                settingsQuery.first?.gridMediaTypeFilter = newFilter
            }
    }

    private var navigationViewWithFocusedValues: some View {
        navigationViewWithSubtitleBindings
            // Action-based focused values for menu commands
            .focusedSceneValue(\.toggleInspector, { showInspector.toggle() })
            .focusedSceneValue(\.importFilesAction, { importFiles() })
            .focusedSceneValue(\.importSubtitlesAction, { importSubtitles() })
            .focusedSceneValue(\.quickLook, { togglePreview() })
            .focusedSceneValue(\.locateExternalLibrary, { library.locateExternalLibrary() })
            .focusedSceneValue(\.newPlaylist, { sidebarViewModel.createPlaylist() })
            .focusedSceneValue(\.newSmartPlaylist, { sidebarViewModel.createSmartPlaylist() })
            .onChange(of: importDestination) { _, newValue in
                settingsQuery.first?.defaultImportLocation = newValue
            }
            .onChange(of: gridShowFilenames) { _, newValue in
                settingsQuery.first?.gridShowFilenames = newValue
            }
            .onChange(of: gridShowCaptions) { _, newValue in
                settingsQuery.first?.gridShowCaptions = newValue
            }
            .onChange(of: animateGIFs) { _, newValue in
                settingsQuery.first?.animateGIFsInGrid = newValue
            }
    }

    private var navigationViewWithSubtitleBindings: some View {
        navigationView
            // Binding-based focused values for menu toggles/pickers
            .focusedSceneValue(\.importDestination, $importDestination)
            .focusedSceneValue(\.gridShowFilenames, $gridShowFilenames)
            .focusedSceneValue(\.gridShowCaptions, $gridShowCaptions)
            .focusedSceneValue(\.animateGIFs, $animateGIFs)
            .focusedSceneValue(\.subtitleShow, $showSubtitles)
            .focusedSceneValue(\.subtitlePosition, $subtitlePosition)
            .focusedSceneValue(\.subtitleFontSize, $subtitleFontSize)
            .focusedSceneValue(\.subtitleOpacity, $subtitleOpacity)
            .onChange(of: showSubtitles) { _, newValue in
                settingsQuery.first?.showSubtitles = newValue
            }
            .onChange(of: subtitlePosition) { _, newValue in
                settingsQuery.first?.subtitlePosition = newValue
            }
            .onChange(of: subtitleFontSize) { _, newValue in
                settingsQuery.first?.subtitleFontSize = newValue
            }
            .onChange(of: subtitleOpacity) { _, newValue in
                settingsQuery.first?.subtitleOpacity = newValue
            }
    }

    private var navigationView: some View {
        NavigationSplitView {
            SidebarView(viewModel: sidebarViewModel)
        } detail: {
            detailContent
        }
        .modifier(ToolbarBackgroundModifier())
        .animation(.easeInOut(duration: 0.25), value: previewItem != nil)
        .searchable(
            text: $gridViewModel.searchText,
            placement: .sidebar,
            prompt: "Search media"
        )
        .inspector(isPresented: $showInspector) {
            inspectorContent
        }
        .dropZone(isTargeted: $isDropTargeted) { urls in
            handleDrop(urls: urls)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
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
                },
                onImportFiles: { importFiles() },
                onToggleInspector: { showInspector.toggle() },
                activePlaylist: activePlaylist
            )
        }
    }

    private func handleDrop(urls: [URL]) {
        Task {
            await performImport(urls: urls)
        }
    }

    private func refreshItems() {
        cachedItems = fetchItems()
    }

    private var activePlaylist: Playlist? {
        if case .playlist(let id) = sidebarViewModel.selectedItem {
            return playlistService.playlist(withID: id)
        }
        return nil
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
        case .unplayableVideos:
            return library.unplayableVideos(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
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
        panel.canChooseFiles = true
        panel.message = "Select media files or folders to import"

        if panel.runModal() == .OK {
            Task {
                await performImport(urls: panel.urls)
            }
        }
    }

    private func importSubtitles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "vtt") ?? .plainText
        ]
        panel.message = "Select subtitle files (SRT/VTT) to match with library videos"

        guard panel.runModal() == .OK else { return }

        var allFiles = [URL]()
        let fm = FileManager.default
        for url in panel.urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        let ext = fileURL.pathExtension.lowercased()
                        if ext == "srt" || ext == "vtt" {
                            allFiles.append(fileURL)
                        }
                    }
                }
            } else {
                allFiles.append(url)
            }
        }

        guard !allFiles.isEmpty else {
            subtitleImportAlert = "No SRT or VTT files found in the selection."
            return
        }

        Task {
            let result = await library.importSubtitles(urls: allFiles)

            var message = "Matched \(result.matched.count) subtitle(s) to videos."
            if !result.unmatched.isEmpty {
                let names = result.unmatched.prefix(5).map(\.lastPathComponent).joined(separator: "\n")
                message += "\n\n\(result.unmatched.count) file(s) had no matching video"
                if result.unmatched.count <= 5 {
                    message += ":\n\(names)"
                } else {
                    message += " (showing first 5):\n\(names)"
                }
            }

            subtitleImportAlert = message
        }
    }

    private func performImport(urls: [URL]) async {
        var options = ImportOptions.default
        if let settings = settingsQuery.first {
            options.importMode = settings.importMode
            options.storageLocation = settings.defaultImportLocation
            options.organizeByDate = settings.importOrganizeByDate
            options.convertIncompatible = settings.convertIncompatibleFormats
            options.deleteOriginalAfterConvert = !settings.keepOriginalAfterConversion
            options.targetFormat = settings.importTargetFormat
        }

        let hasFolders = urls.contains { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        if hasFolders {
            guard let (_, folderGroups) = try? await library.importFolders(urls: urls, options: options) else { return }

            if settingsQuery.first?.createPlaylistsFromFolders == true {
                for group in folderGroups {
                    let name = uniquePlaylistName(for: group.name)
                    let playlist = playlistService.createPlaylist(name: name, type: .manual)
                    playlistService.addItems(group.items, to: playlist)
                }
            }
        } else {
            _ = try? await library.importFiles(urls: urls, options: options)
        }
    }

    private func uniquePlaylistName(for baseName: String) -> String {
        let existingNames = Set(playlistService.playlists.map(\.name))
        if !existingNames.contains(baseName) {
            return baseName
        }
        var counter = 2
        while existingNames.contains("\(baseName) \(counter)") {
            counter += 1
        }
        return "\(baseName) \(counter)"
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
        if showInspector {
            actualInspectorContent
        } else {
            Color.clear
                .frame(minWidth: 280)
        }
    }

    @ViewBuilder
    private var actualInspectorContent: some View {
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
