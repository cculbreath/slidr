import SwiftUI
import SwiftData

struct GridToolbarContent: ToolbarContent {
    @Bindable var viewModel: GridViewModel
    let settings: AppSettings?
    let itemsEmpty: Bool
    let onImport: () -> Void
    let onToggleGIFAnimation: () -> Void
    let onToggleCaptions: () -> Void
    let onToggleFilenames: () -> Void
    let onStartSlideshow: () -> Void

    var body: some ToolbarContent {
        // MARK: - Navigation (left side)
        ToolbarItem(placement: .navigation) {
            Button {
                onStartSlideshow()
            } label: {
                Label("Slideshow", systemImage: "play.rectangle.on.rectangle")
            }
            .disabled(itemsEmpty)
        }

        ToolbarItem(placement: .navigation) {
            Button {
                onImport()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        }

        // MARK: - Secondary Actions (center-left)
        ToolbarItem(placement: .secondaryAction) {
            Picker("Size", selection: $viewModel.thumbnailSize) {
                Label("Large", systemImage: "square.grid.2x2").tag(ThumbnailSize.large)
                Label("Medium", systemImage: "square.grid.3x2").tag(ThumbnailSize.medium)
                Label("Small", systemImage: "square.grid.3x3").tag(ThumbnailSize.small)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }

        ToolbarItem(placement: .secondaryAction) {
            showMenu
        }

        ToolbarItem(placement: .secondaryAction) {
            Button {
                onToggleGIFAnimation()
            } label: {
                Label(
                    settings?.animateGIFsInGrid == true ? "GIFs: On" : "GIFs: Off",
                    image: settings?.animateGIFsInGrid == true ? "custom.gifs.pause" : "custom.gifs.play"
                )
            }
            .help("Toggle GIF animation in grid")
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            filterMenu
            sortMenu
        }

        // MARK: - Primary Actions (right side)
        ToolbarItem(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .toggleInspector, object: nil)
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
        }
    }

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
            Label("Show", systemImage: "eye")
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
            Label("Filter", systemImage: viewModel.mediaTypeFilter.isEmpty ? "circle.lefthalf.filled.righthalf.striped.horizontal.inverse" : "circle.lefthalf.filled.righthalf.striped.horizontal.inverse")
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
            Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}
