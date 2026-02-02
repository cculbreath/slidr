import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.transcriptStore) private var transcriptStore
    @Environment(AIProcessingCoordinator.self) private var aiCoordinator
    @Query private var settingsQuery: [AppSettings]

    @State private var sidebarViewModel = SidebarViewModel()
    @State private var gridViewModel = GridViewModel()
    @State private var slideshowViewModel = SlideshowViewModel()
    @State private var transcriptSearchService = TranscriptSearchService()
    @State private var toolbarCoordinator = GridToolbarCoordinator()
    @State private var menuCoordinator = MenuSettingsCoordinator()
    @State private var showSlideshow = false
    @State private var externalSlideshowActive = false
    @State private var showInspector = false
    @State private var isDropTargeted = false
    @State private var previewItem: MediaItem?
    @State private var cachedItems: [MediaItem] = []
    @State private var subtitleImportAlert: String?
    @State private var transcriptSeekAction: ((TimeInterval) -> Void)?
    @State private var pendingTranscriptSeek: TimeInterval?
    @State private var aiStatusWindow: AIStatusWindowController?

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
            toolbarCoordinator.updatePaletteSelectedItems([active[newIndex]])
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

    private var allTags: [String] {
        Array(Set(cachedItems.flatMap(\.tags))).sorted()
    }

    private var importProgressSubtitle: String? {
        guard let progress = library.importProgress else { return nil }
        return "\(progress.currentItem + 1) of \(progress.totalItems): \(progress.currentFilename)"
    }

    // MARK: - Main Content

    private var mainContent: some View {
        navigationView
            .modifier(ActionFocusedValuesModifier(
                toggleInspector: { showInspector.toggle() },
                importFiles: { importFiles() },
                importSubtitles: { importSubtitles() },
                quickLook: { togglePreview() },
                locateExternalLibrary: { library.locateExternalLibrary() },
                newPlaylist: { sidebarViewModel.createPlaylist() },
                newSmartPlaylist: { sidebarViewModel.createSmartPlaylist() },
                toggleTagPalette: { toolbarCoordinator.toggleTagPalette() }
            ))
            .modifier(AIFocusedValuesModifier(
                coordinator: menuCoordinator,
                processSelected: { aiProcessSelected() },
                tagSelected: { aiTagSelected() },
                summarizeSelected: { aiSummarizeSelected() },
                transcribeSelected: { aiTranscribeSelected() },
                processUntagged: { aiProcessUntagged() },
                processUntranscribed: { aiProcessUntranscribed() },
                showStatusWindow: { aiStatusWindow?.show() }
            ))
            .modifier(BrowserFocusedValuesModifier(coordinator: menuCoordinator))
            .modifier(SlideshowFocusedValuesModifier(coordinator: menuCoordinator))
            .modifier(FilterFocusedValuesModifier(gridViewModel: gridViewModel, allTags: allTags))
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
            .onChange(of: showSlideshow) { _, isSlideshow in
                toolbarCoordinator.toolbar.isVisible = !isSlideshow
            }
            .onAppear {
                sidebarViewModel.configure(with: playlistService)
                transcriptSearchService.configure(transcriptStore: transcriptStore)
                if sidebarViewModel.selectedItem == nil {
                    sidebarViewModel.selectedItem = .allMedia
                }
                if let settings = settingsQuery.first {
                    gridViewModel.sortOrder = settings.defaultSortOrder
                    gridViewModel.sortAscending = settings.defaultSortAscending
                    gridViewModel.mediaTypeFilter = settings.gridMediaTypeFilter
                    gridViewModel.browserMode = settings.browserViewMode
                    menuCoordinator.load(from: settings, gridViewModel: gridViewModel)
                }
                refreshItems()
                let count = settingsQuery.first?.scrubThumbnailCount ?? 100
                library.backgroundGenerateMissingScrubThumbnails(count: count)
                if aiStatusWindow == nil {
                    aiStatusWindow = AIStatusWindowController(coordinator: aiCoordinator)
                }
            }
            .onChange(of: aiCoordinator.isProcessing) { _, isProcessing in
                if isProcessing {
                    aiStatusWindow?.show()
                } else {
                    aiStatusWindow?.scheduleAutoDismiss()
                }
            }
            .onChange(of: settingsQuery.first?.aiAutoProcessOnImport) { _, newValue in
                menuCoordinator.aiAutoProcess = newValue ?? false
            }
            .onChange(of: settingsQuery.first?.aiAutoTranscribeOnImport) { _, newValue in
                menuCoordinator.aiAutoTranscribe = newValue ?? false
            }
            .onChange(of: settingsQuery.first?.aiTagMode) { _, newValue in
                menuCoordinator.aiTagMode = newValue ?? .generateNew
            }
            .onChange(of: gridViewModel.searchText) { _, newText in
                transcriptSearchService.search(query: newText, in: cachedItems)
            }
            .onChange(of: gridViewModel.mediaTypeFilter) { _, newFilter in
                refreshItems()
                settingsQuery.first?.gridMediaTypeFilter = newFilter
            }
            .onChange(of: gridViewModel.browserMode) { _, newValue in
                menuCoordinator.browserViewMode = newValue
            }
    }

    // MARK: - Navigation View

    private var navigationView: some View {
        NavigationSplitView {
            SidebarView(viewModel: sidebarViewModel, searchText: $gridViewModel.searchText)
        } detail: {
            detailContent
        }
        .animation(.easeInOut(duration: 0.25), value: previewItem != nil)
        .environment(\.transcriptSeekAction, transcriptSeekAction)
        .modifier(WindowToolbarModifier(coordinator: toolbarCoordinator))
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

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        ZStack(alignment: .topLeading) {
            if let previewItem {
                MediaPreviewView(item: previewItem, items: cachedItems, library: library, onSeekAction: $transcriptSeekAction) {
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
                    activePlaylist: activePlaylist,
                    isDecodeErrorsView: sidebarViewModel.selectedItem == .decodeErrors,
                    toolbarCoordinator: toolbarCoordinator
                )
            }

            if transcriptSearchService.isPopupVisible && previewItem == nil {
                TranscriptSearchPopup(
                    results: transcriptSearchService.results,
                    query: gridViewModel.searchText,
                    onSelect: { selectTranscriptResult($0) },
                    onDismiss: { transcriptSearchService.clearResults() }
                )
                .padding(.top, 8)
                .padding(.leading, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: transcriptSearchService.isPopupVisible)
        .onChange(of: transcriptSeekAction != nil) { _, hasAction in
            if hasAction, let pending = pendingTranscriptSeek {
                let seekAction = transcriptSeekAction
                pendingTranscriptSeek = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    seekAction?(pending)
                }
            }
        }
    }

    // MARK: - Items & Selection

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
        case .decodeErrors:
            return library.decodeErrorVideos(sortedBy: gridViewModel.sortOrder, ascending: gridViewModel.sortAscending)
        case .playlist(let id):
            if let playlist = playlistService.playlist(withID: id) {
                return playlistService.items(for: playlist)
            }
            return []
        }
    }

    // MARK: - Slideshow

    private func startSlideshow(items: [MediaItem], startIndex: Int) {
        slideshowViewModel.start(with: items, startingAt: startIndex)

        let settings = settingsQuery.first
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens.first

        if settings?.useAllMonitors == true,
           screens.count > 1,
           let externalScreen = screens.first(where: { $0 != mainScreen }) {
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

        let selectedIDs = gridViewModel.selectedItems
        let resolved = cachedItems.filter { selectedIDs.contains($0.id) }
        toolbarCoordinator.updatePaletteSelectedItems(resolved)
    }

    // MARK: - Import

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

        var importedItems: [MediaItem] = []

        let hasFolders = urls.contains { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        if hasFolders {
            guard let (result, folderGroups) = try? await library.importFolders(urls: urls, options: options) else { return }
            importedItems = result.imported

            if settingsQuery.first?.createPlaylistsFromFolders == true {
                for group in folderGroups {
                    let name = uniquePlaylistName(for: group.name)
                    let playlist = playlistService.createPlaylist(name: name, type: .manual)
                    playlistService.addItems(group.items, to: playlist)
                }
            }
        } else {
            if let result = try? await library.importFiles(urls: urls, options: options) {
                importedItems = result.imported
            }
        }

        if let settings = settingsQuery.first, !importedItems.isEmpty {
            if settings.aiAutoProcessOnImport {
                Task {
                    await aiCoordinator.processItems(importedItems, settings: settings, allTags: allTags, library: library, modelContext: modelContext)
                }
            } else if settings.aiAutoTranscribeOnImport {
                let videos = importedItems.filter { $0.isVideo && $0.hasAudio == true }
                if !videos.isEmpty {
                    Task {
                        await aiCoordinator.transcribeItems(videos, settings: settings, library: library, modelContext: modelContext)
                    }
                }
            }
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

    // MARK: - Preview

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

    private func selectTranscriptResult(_ result: TranscriptSearchResult) {
        gridViewModel.selectedItems = [result.mediaItem.id]
        pendingTranscriptSeek = result.cue.startTime
        withAnimation(.easeInOut(duration: 0.25)) {
            previewItem = result.mediaItem
        }
        transcriptSearchService.clearResults()
        gridViewModel.searchText = ""
    }

    // MARK: - AI Actions

    private func selectedItems() -> [MediaItem] {
        cachedItems.filter { gridViewModel.selectedItems.contains($0.id) }
    }

    private func firstSelectedItem() -> MediaItem? {
        guard let selectedID = gridViewModel.selectedItems.first else { return nil }
        return cachedItems.first { $0.id == selectedID }
    }

    private func aiProcessSelected() {
        let items = selectedItems()
        guard !items.isEmpty, let settings = settingsQuery.first else { return }
        Task { await aiCoordinator.processItems(items, settings: settings, allTags: allTags, library: library, modelContext: modelContext) }
    }

    private func aiTagSelected() {
        guard let item = firstSelectedItem(), let settings = settingsQuery.first else { return }
        Task { await aiCoordinator.tagItem(item, settings: settings, allTags: allTags, library: library, modelContext: modelContext) }
    }

    private func aiSummarizeSelected() {
        guard let item = firstSelectedItem(), let settings = settingsQuery.first else { return }
        Task { await aiCoordinator.summarizeItem(item, settings: settings, library: library, modelContext: modelContext) }
    }

    private func aiTranscribeSelected() {
        guard let item = firstSelectedItem(), let settings = settingsQuery.first else { return }
        Task { await aiCoordinator.transcribeItem(item, settings: settings, modelContext: modelContext, library: library) }
    }

    private func aiProcessUntagged() {
        let untagged = cachedItems.filter { $0.tags.isEmpty }
        guard !untagged.isEmpty, let settings = settingsQuery.first else { return }
        Task { await aiCoordinator.processItems(untagged, settings: settings, allTags: allTags, library: library, modelContext: modelContext) }
    }

    private func aiProcessUntranscribed() {
        let untranscribed = cachedItems.filter { $0.isVideo && $0.hasAudio == true && $0.transcriptText == nil }
        guard !untranscribed.isEmpty, let settings = settingsQuery.first else { return }
        Task { await aiCoordinator.transcribeItems(untranscribed, settings: settings, library: library, modelContext: modelContext) }
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
