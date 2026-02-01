import SwiftUI
import SwiftData

struct GridToolbarContent: CustomizableToolbarContent {
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
    let onShowAdvancedFilter: () -> Void

    private var gifAnimationEnabled: Bool { settings?.animateGIFsInGrid ?? false }
    private var hoverScrubEnabled: Bool { settings?.gridVideoHoverScrub ?? false }
    private var hasMediaTypeFilter: Bool { !viewModel.mediaTypeFilter.isEmpty }
    private var hasProductionTypeFilter: Bool { !viewModel.productionTypeFilter.isEmpty }
    private var hasTagFilter: Bool { !viewModel.tagFilter.isEmpty }
    private var hasCaptionsEnabled: Bool { (settings?.gridShowCaptions ?? true) || (settings?.gridShowFilenames ?? false) }
    private var hasAdvancedFilter: Bool { viewModel.advancedFilter != nil }

    var body: some CustomizableToolbarContent {
        navigationItems
        displayItems
        filterItems
        sortAndActionItems
    }

    // MARK: - Toolbar Groups

    @ToolbarContentBuilder
    private var navigationItems: some CustomizableToolbarContent {
        ToolbarItem(id: "slideshow", placement: .navigation) {
            Button {
                onStartSlideshow()
            } label: {
                Label("Slideshow", systemImage: "play.rectangle.on.rectangle")
            }
            .disabled(itemsEmpty)
            .help("Start Slideshow")
        }

        ToolbarItem(id: "import", placement: .navigation) {
            Button {
                onImport()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import Files")
        }

        ToolbarItem(id: "thumbnailSize", placement: .secondaryAction) {
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
        }
    }

    @ToolbarContentBuilder
    private var displayItems: some CustomizableToolbarContent {
        ToolbarItem(id: "captionVisibility", placement: .secondaryAction) {
            showMenu
        }

        ToolbarItem(id: "hoverScrub", placement: .secondaryAction) {
            Button {
                onToggleHoverScrub()
            } label: {
                Label("Scrubbing", systemImage: "hand.point.up.braille")
                    .foregroundStyle(hoverScrubEnabled ? Color.accentColor : .primary)
            }
            .help("Toggle video scrub on hover")
        }

        ToolbarItem(id: "gifAnimation", placement: .secondaryAction) {
            Button {
                onToggleGIFAnimation()
            } label: {
                Label("Autoplay GIFs", systemImage: "waveform.path.ecg.rectangle")
                    .foregroundStyle(gifAnimationEnabled ? Color.accentColor : .primary)
            }
            .help("Toggle GIF animation in grid")
        }
    }

    @ToolbarContentBuilder
    private var filterItems: some CustomizableToolbarContent {
        ToolbarItem(id: "mediaTypeFilter", placement: .secondaryAction) {
            filterMenu
        }

        ToolbarItem(id: "productionFilter", placement: .secondaryAction) {
            productionFilterMenu
        }

        ToolbarItem(id: "tagFilter", placement: .secondaryAction) {
            tagFilterMenu
        }
    }

    @ToolbarContentBuilder
    private var sortAndActionItems: some CustomizableToolbarContent {
        ToolbarItem(id: "advancedFilter", placement: .secondaryAction) {
            Button {
                onShowAdvancedFilter()
            } label: {
                Label("Advanced Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .symbolVariant(hasAdvancedFilter ? .fill : .none)
                    .foregroundStyle(hasAdvancedFilter ? Color.accentColor : .primary)
            }
            .help("Open advanced filter")
        }

        ToolbarItem(id: "sortOrder", placement: .secondaryAction) {
            sortMenu
        }

        ToolbarItem(id: "inspector", placement: .primaryAction) {
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
            Label("Media Types", systemImage: "square.stack.3d.forward.dottedline")
                .foregroundStyle(hasMediaTypeFilter ? Color.accentColor : .primary)
        }
    }

    private var productionFilterMenu: some View {
        Menu {
            Button {
                viewModel.productionTypeFilter = []
            } label: {
                HStack {
                    Text("All")
                    if viewModel.productionTypeFilter.isEmpty {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(ProductionType.allCases, id: \.self) { type in
                Button {
                    if viewModel.productionTypeFilter.contains(type) {
                        viewModel.productionTypeFilter.remove(type)
                    } else {
                        viewModel.productionTypeFilter.insert(type)
                    }
                } label: {
                    HStack {
                        Label(type.displayName, systemImage: type.iconName)
                        if viewModel.productionTypeFilter.contains(type) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Production", systemImage: "film")
                .foregroundStyle(hasProductionTypeFilter ? Color.accentColor : .primary)
        }
    }

    private var tagFilterMenu: some View {
        TagFilterPopover(
            allTags: allTags,
            tagFilter: $viewModel.tagFilter,
            hasTagFilter: hasTagFilter
        )
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
            HStack(spacing: 2) {
                Label("Tags", systemImage: "tag")
                    .symbolVariant(hasTagFilter ? .fill : .none)
                    .foregroundStyle(hasTagFilter ? Color.accentColor : .primary)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(hasTagFilter ? Color.accentColor : .primary)
            }
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
