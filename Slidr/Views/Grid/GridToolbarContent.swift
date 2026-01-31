import SwiftUI
import SwiftData

struct GridToolbarContent: ToolbarContent {
    @Bindable var viewModel: GridViewModel
    let settings: AppSettings?
    let itemsEmpty: Bool
    let allTags: [String]
    let onImport: () -> Void
    let onToggleGIFAnimation: () -> Void
    let onToggleHoverScrub: () -> Void
    let onToggleCaptions: () -> Void
    let onToggleFilenames: () -> Void
    let onStartSlideshow: () -> Void
    let onToggleInspector: () -> Void

    private var gifAnimationEnabled: Bool { settings?.animateGIFsInGrid ?? false }
    private var hoverScrubEnabled: Bool { settings?.gridVideoHoverScrub ?? false }
    private var hasMediaTypeFilter: Bool { !viewModel.mediaTypeFilter.isEmpty }
    private var hasRatingFilter: Bool { viewModel.ratingFilterEnabled && !viewModel.ratingFilter.isEmpty }
    private var hasTagFilter: Bool { !viewModel.tagFilter.isEmpty }
    private var hasCaptionsEnabled: Bool { (settings?.gridShowCaptions ?? true) || (settings?.gridShowFilenames ?? false) }
    private var hasSubtitleFilter: Bool { viewModel.subtitleFilter }

    var body: some ToolbarContent {
        // Layout: [sidebar, slideshow, import] [spacer] [size, captions] [spacer] [gifs, scrub] [spacer] [rating, tags, type, sort] [spacer] [inspector]

        // Group 1: Slideshow, Import (sidebar toggle is provided by NavigationSplitView)
        ToolbarItemGroup(placement: .navigation) {
            Button {
                onStartSlideshow()
            } label: {
                Label("Slideshow", systemImage: "play.rectangle.on.rectangle")
            }
            .disabled(itemsEmpty)
            .help("Start Slideshow")

            Button {
                onImport()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import Files")
        }

        ToolbarSpacer(.flexible)

        // Group 2: Thumbnail Size, Captions
        ToolbarItemGroup {
            LabeledContent("Thumbnail Size") {
                Picker("Size", selection: $viewModel.thumbnailSize) {
                    Label("Large", systemImage: "square.grid.2x2").tag(ThumbnailSize.large)
                    Label("Medium", systemImage: "square.grid.3x2").tag(ThumbnailSize.medium)
                    Label("Small", systemImage: "square.grid.3x3").tag(ThumbnailSize.small)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            showMenu
        }

        ToolbarSpacer(.flexible)

        // Group 3: Autoplay GIFs, Scrubbing
        ToolbarItemGroup {
            Button {
                onToggleGIFAnimation()
            } label: {
                Label("Autoplay GIFs", systemImage: "play.circle")
                    .symbolVariant(gifAnimationEnabled ? .fill : .none)
                    .foregroundStyle(gifAnimationEnabled ? Color.accentColor : .primary)
            }
            .help("Toggle GIF animation in grid")

            Button {
                onToggleHoverScrub()
            } label: {
                Label("Scrubbing", systemImage: "hand.point.up.braille")
                    .foregroundStyle(hoverScrubEnabled ? Color.accentColor : .primary)
            }
            .help("Toggle video scrub on hover")
        }

        ToolbarSpacer(.flexible)

        // Group 4: Subtitle, Summary Search, Rating, Tags, Media Type, Sort
        ToolbarItemGroup {
            Button {
                viewModel.subtitleFilter.toggle()
            } label: {
                Label("Has Subtitle", systemImage: "captions.bubble")
                    .symbolVariant(hasSubtitleFilter ? .fill : .none)
                    .foregroundStyle(hasSubtitleFilter ? Color.accentColor : .primary)
            }
            .help("Show only items with subtitles")

            Button {
                viewModel.searchIncludesSummary.toggle()
            } label: {
                Label("Search Summaries", systemImage: "text.magnifyingglass")
                    .foregroundStyle(viewModel.searchIncludesSummary ? Color.accentColor : .primary)
            }
            .help("Include AI summaries in search results")

            ratingFilterMenu
            tagFilterMenu
            filterMenu
            sortMenu
        }

        ToolbarSpacer(.flexible)

        // Group 5: Inspector
        ToolbarItem(placement: .primaryAction) {
            Button {
                onToggleInspector()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle Inspector")
        }
    }

    // MARK: - Menu Views

    private var showMenu: some View {
        Menu {
            Toggle("Caption", isOn: Binding(
                get: { settings?.gridShowCaptions ?? true },
                set: { _ in onToggleCaptions() }
            ))
            Toggle("Filename", isOn: Binding(
                get: { settings?.gridShowFilenames ?? false },
                set: { _ in onToggleFilenames() }
            ))
        } label: {
            Label("Captions", systemImage: "eye")
                .symbolVariant(hasCaptionsEnabled ? .fill : .none)
                .foregroundStyle(hasCaptionsEnabled ? Color.accentColor : .primary)
        }
    }

    private var filterMenu: some View {
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
            // Static icon structure - only color/variant changes
            Label("Media Types", systemImage: "line.3.horizontal.decrease.circle")
                .symbolVariant(hasMediaTypeFilter ? .fill : .none)
                .foregroundStyle(hasMediaTypeFilter ? Color.accentColor : .primary)
        }
    }

    private var tagFilterMenu: some View {
        TagFilterPopover(
            allTags: allTags,
            tagFilter: $viewModel.tagFilter,
            hasTagFilter: hasTagFilter
        )
    }

    private var ratingFilterMenu: some View {
        Menu {
            // Star ratings 1-5
            ForEach(1...5, id: \.self) { stars in
                Button {
                    toggleRating(stars)
                } label: {
                    HStack {
                        Text(String(repeating: "★", count: stars))
                        Spacer()
                        if viewModel.ratingFilter.contains(stars) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            // No rating option
            Button {
                toggleRating(0)
            } label: {
                HStack {
                    Text("No Rating")
                    Spacer()
                    if viewModel.ratingFilter.contains(0) {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            // Enable/Disable filter (radio)
            Button {
                viewModel.ratingFilterEnabled = true
            } label: {
                HStack {
                    Text("Filter Enabled")
                    Spacer()
                    if viewModel.ratingFilterEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                viewModel.ratingFilterEnabled = false
            } label: {
                HStack {
                    Text("Filter Disabled")
                    Spacer()
                    if !viewModel.ratingFilterEnabled {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            // Static icon structure
            Label("Rating", systemImage: "star")
                .symbolVariant(hasRatingFilter ? .fill : .none)
                .foregroundStyle(hasRatingFilter ? Color.accentColor : .primary)
        }
    }

    private func toggleRating(_ rating: Int) {
        if viewModel.ratingFilter.contains(rating) {
            viewModel.ratingFilter.remove(rating)
        } else {
            viewModel.ratingFilter.insert(rating)
        }
        // Auto-enable filter when selecting ratings
        if !viewModel.ratingFilter.isEmpty {
            viewModel.ratingFilterEnabled = true
        }
    }

    private var sortMenu: some View {
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
            Label("Sort", systemImage: "arrow.up.arrow.down.circle")
        }
    }
}

// MARK: - Tag Filter Popover

private struct TagFilterPopover: View {
    let allTags: [String]
    @Binding var tagFilter: Set<String>
    let hasTagFilter: Bool

    @State private var searchText = ""
    @State private var isPresented = false

    private var filteredTags: [String] {
        if searchText.isEmpty { return allTags }
        let query = searchText.lowercased()
        return allTags.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Tags", systemImage: "tag")
                .symbolVariant(hasTagFilter ? .fill : .none)
                .foregroundStyle(hasTagFilter ? Color.accentColor : .primary)
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search tags...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)

                Divider()

                // Clear filter button
                if hasTagFilter {
                    Button {
                        tagFilter.removeAll()
                    } label: {
                        Label("Clear Tag Filter", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                    Divider()
                }

                // Tag list
                if allTags.isEmpty {
                    Text("No tags in library")
                        .foregroundStyle(.secondary)
                        .padding()
                } else if filteredTags.isEmpty {
                    Text("No matching tags")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredTags, id: \.self) { tag in
                                tagRow(tag)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
            }
            .frame(width: 240)
        }
    }

    private func tagRow(_ tag: String) -> some View {
        Button {
            if tagFilter.contains(tag) {
                tagFilter.remove(tag)
            } else {
                tagFilter.insert(tag)
            }
        } label: {
            HStack {
                Text(tag)
                    .lineLimit(1)
                Spacer()
                if tagFilter.contains(tag) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
