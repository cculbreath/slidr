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

    private var gifAnimationEnabled: Bool { settings?.animateGIFsInGrid ?? false }
    private var hoverScrubEnabled: Bool { settings?.gridVideoHoverScrub ?? false }
    private var hasMediaTypeFilter: Bool { !viewModel.mediaTypeFilter.isEmpty }
    private var hasRatingFilter: Bool { viewModel.ratingFilterEnabled && !viewModel.ratingFilter.isEmpty }
    private var hasTagFilter: Bool { !viewModel.tagFilter.isEmpty }
    private var hasCaptionsEnabled: Bool { (settings?.gridShowCaptions ?? true) || (settings?.gridShowFilenames ?? false) }

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

        // Group 4: Rating, Tags, Media Type, Sort
        ToolbarItemGroup {
            ratingFilterMenu
            tagFilterMenu
            filterMenu
            sortMenu
        }

        ToolbarSpacer(.flexible)

        // Group 5: Inspector
        ToolbarItem(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .toggleInspector, object: nil)
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
        Menu {
            if hasTagFilter {
                Button {
                    viewModel.tagFilter.removeAll()
                } label: {
                    Label("Clear Tag Filter", systemImage: "xmark.circle")
                }
                Divider()
            }

            if allTags.isEmpty {
                Text("No tags in library")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allTags, id: \.self) { tag in
                    Button {
                        if viewModel.tagFilter.contains(tag) {
                            viewModel.tagFilter.remove(tag)
                        } else {
                            viewModel.tagFilter.insert(tag)
                        }
                    } label: {
                        HStack {
                            Text(tag)
                            Spacer()
                            if viewModel.tagFilter.contains(tag) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            // Static label structure
            Label("Tags", systemImage: "tag")
                .symbolVariant(hasTagFilter ? .fill : .none)
                .foregroundStyle(hasTagFilter ? Color.accentColor : .primary)
        }
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
