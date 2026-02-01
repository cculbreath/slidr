import SwiftUI
import AppKit

private enum SubtitleFontSizeOption: CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: Double { size }

    var size: Double {
        switch self {
        case .small: return 12
        case .medium: return 16
        case .large: return 20
        case .extraLarge: return 24
        }
    }

    var label: String {
        switch self {
        case .small: return "Small (12pt)"
        case .medium: return "Medium (16pt)"
        case .large: return "Large (20pt)"
        case .extraLarge: return "Extra Large (24pt)"
        }
    }
}

private enum SubtitleOpacityOption: CaseIterable, Identifiable {
    case quarter, half, threeQuarter, full

    var id: Double { value }

    var value: Double {
        switch self {
        case .quarter: return 0.25
        case .half: return 0.5
        case .threeQuarter: return 0.75
        case .full: return 1.0
        }
    }

    var label: String {
        switch self {
        case .quarter: return "25%"
        case .half: return "50%"
        case .threeQuarter: return "75%"
        case .full: return "100%"
        }
    }
}

struct SlidrCommands: Commands {
    // MARK: - Action FocusedValues
    @FocusedValue(\.startSlideshow) var startSlideshow
    @FocusedValue(\.selectAll) var selectAll
    @FocusedValue(\.deselectAll) var deselectAll
    @FocusedValue(\.deleteSelected) var deleteSelected
    @FocusedValue(\.toggleInspector) var toggleInspector
    @FocusedValue(\.importFilesAction) var importFiles
    @FocusedValue(\.importSubtitlesAction) var importSubtitles
    @FocusedValue(\.locateExternalLibrary) var locateExternalLibrary
    @FocusedValue(\.newPlaylist) var newPlaylist
    @FocusedValue(\.newSmartPlaylist) var newSmartPlaylist
    @FocusedValue(\.focusSearch) var focusSearch
    @FocusedValue(\.increaseThumbnailSize) var increaseThumbnailSize
    @FocusedValue(\.decreaseThumbnailSize) var decreaseThumbnailSize
    @FocusedValue(\.resetThumbnailSize) var resetThumbnailSize
    @FocusedValue(\.revealInFinder) var revealInFinder
    @FocusedValue(\.toggleTagPalette) var toggleTagPalette

    // MARK: - Filter Action FocusedValues
    @FocusedValue(\.showAdvancedFilter) var showAdvancedFilter
    @FocusedValue(\.clearAllFilters) var clearAllFilters

    // MARK: - Filter Binding FocusedValues
    @FocusedValue(\.mediaTypeFilterBinding) var mediaTypeFilterBinding
    @FocusedValue(\.productionTypeFilterBinding) var productionTypeFilterBinding
    @FocusedValue(\.subtitleFilterBinding) var subtitleFilterBinding
    @FocusedValue(\.captionFilterBinding) var captionFilterBinding
    @FocusedValue(\.ratingFilterEnabledBinding) var ratingFilterEnabledBinding
    @FocusedValue(\.ratingFilterBinding) var ratingFilterBinding
    @FocusedValue(\.tagFilterBinding) var tagFilterBinding
    @FocusedValue(\.sortOrderBinding) var sortOrderBinding
    @FocusedValue(\.sortAscendingBinding) var sortAscendingBinding
    @FocusedValue(\.allTags) var allTags

    // MARK: - Binding FocusedValues
    @FocusedValue(\.importDestination) var importDestination
    @FocusedValue(\.gridShowFilenames) var gridShowFilenames
    @FocusedValue(\.gridShowCaptions) var gridShowCaptions
    @FocusedValue(\.animateGIFs) var animateGIFs
    @FocusedValue(\.videoHoverScrub) var videoHoverScrub
    @FocusedValue(\.browserViewMode) var browserViewMode
    @FocusedValue(\.loopSlideshow) var loopSlideshow
    @FocusedValue(\.shuffleSlideshow) var shuffleSlideshow
    @FocusedValue(\.slideshowTransition) var slideshowTransition
    @FocusedValue(\.listColumnCustomization) var listColumnCustomization
    @FocusedValue(\.subtitleShow) var subtitleShow
    @FocusedValue(\.subtitlePosition) var subtitlePosition
    @FocusedValue(\.subtitleFontSize) var subtitleFontSize
    @FocusedValue(\.subtitleOpacity) var subtitleOpacity

    var body: some Commands {
        helpCommands
        pasteboardCommands
        searchCommands
        fileCommands
        viewCommands
        browserCommands
        slideshowCommands
        subtitleCommands
    }

    // MARK: - Help Menu

    private var helpCommands: some Commands {
        CommandGroup(replacing: .help) {
            Button("Slidr Help") {
                NSApp.sendAction(#selector(NSApplication.showHelp(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }

    // MARK: - Edit Menu (Pasteboard)

    private var pasteboardCommands: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Delete") {
                NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: nil)
            }

            Divider()

            Button("Select All") {
                selectAll?()
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Deselect All") {
                deselectAll?()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }

    // MARK: - Search

    private var searchCommands: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()

            Button("Find...") {
                focusSearch?()
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    // MARK: - File Menu

    private var fileCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import Files...") {
                importFiles?()
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Import Subtitles...") {
                importSubtitles?()
            }

            Menu("Import Destination") {
                if let importDestination {
                    Picker(selection: importDestination) {
                        Text("Local Library").tag(StorageLocation.local)
                        Text("External Library").tag(StorageLocation.external)
                        Text("Reference in Place").tag(StorageLocation.referenced)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                }
            }

            Button("Locate External Library...") {
                locateExternalLibrary?()
            }

            Divider()

            Button("New Playlist") {
                newPlaylist?()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Smart Playlist") {
                newSmartPlaylist?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Delete Selected") {
                deleteSelected?()
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
    }

    // MARK: - View Menu

    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Inspector") {
                toggleInspector?()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Show Tag Palette") {
                toggleTagPalette?()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("Reveal in Finder") {
                revealInFinder?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }

    // MARK: - Browser Menu

    private var browserCommands: some Commands {
        CommandMenu("Browser") {
            // View mode switching
            Button("As Grid") {
                browserViewMode?.wrappedValue = .grid
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("As List") {
                browserViewMode?.wrappedValue = .list
            }
            .keyboardShortcut("2", modifiers: .command)

            Divider()

            // Show Columns submenu
            showColumnsMenu

            Divider()

            // Filter submenu (moved from top-level Filter menu)
            filterMenu

            Divider()

            // Display toggles
            if let gridShowCaptions {
                Toggle("Show Captions", isOn: gridShowCaptions)
            }

            if let gridShowFilenames {
                Toggle("Show Filenames", isOn: gridShowFilenames)
            }

            Divider()

            if let videoHoverScrub {
                Toggle("Enable Scrubbing", isOn: videoHoverScrub)
            }

            if let animateGIFs {
                Toggle("Animate GIFs", isOn: animateGIFs)
            }

            Divider()

            // Thumbnail sizing
            Button("Larger Thumbnails") {
                increaseThumbnailSize?()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Smaller Thumbnails") {
                decreaseThumbnailSize?()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Thumbnail Size") {
                resetThumbnailSize?()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }

    // MARK: - Show Columns Submenu

    @ViewBuilder
    private var showColumnsMenu: some View {
        Menu("Show Columns") {
            if let listColumnCustomization {
                ForEach(ListColumnID.allCases.filter({ $0 != .thumbnail })) { column in
                    let isVisible = listColumnCustomization.wrappedValue[visibility: column.rawValue] != .hidden
                    Button {
                        listColumnCustomization.wrappedValue[visibility: column.rawValue] = isVisible ? .hidden : .visible
                    } label: {
                        HStack {
                            Text(column.displayName)
                            if isVisible {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } else {
                ForEach(ListColumnID.allCases.filter({ $0 != .thumbnail })) { column in
                    Button {
                    } label: {
                        HStack {
                            Text(column.displayName)
                            if column.defaultVisible {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(true)
                }
            }
        }
    }

    // MARK: - Filter Submenu

    @ViewBuilder
    private var filterMenu: some View {
        Menu("Filter") {
            Menu("Media Type") {
                Button {
                    mediaTypeFilterBinding?.wrappedValue = []
                } label: {
                    HStack {
                        Text("All")
                        if mediaTypeFilterBinding?.wrappedValue.isEmpty ?? true {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(MediaType.allCases, id: \.self) { type in
                    Button {
                        guard let binding = mediaTypeFilterBinding else { return }
                        if binding.wrappedValue.contains(type) {
                            binding.wrappedValue.remove(type)
                        } else {
                            binding.wrappedValue.insert(type)
                        }
                    } label: {
                        HStack {
                            Text(type.rawValue.capitalized)
                            if mediaTypeFilterBinding?.wrappedValue.contains(type) ?? false {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Menu("Production Type") {
                Button {
                    productionTypeFilterBinding?.wrappedValue = []
                } label: {
                    HStack {
                        Text("All")
                        if productionTypeFilterBinding?.wrappedValue.isEmpty ?? true {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(ProductionType.allCases, id: \.self) { type in
                    Button {
                        guard let binding = productionTypeFilterBinding else { return }
                        if binding.wrappedValue.contains(type) {
                            binding.wrappedValue.remove(type)
                        } else {
                            binding.wrappedValue.insert(type)
                        }
                    } label: {
                        HStack {
                            Label(type.displayName, systemImage: type.iconName)
                            if productionTypeFilterBinding?.wrappedValue.contains(type) ?? false {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Menu("Rating") {
                ForEach(1...5, id: \.self) { stars in
                    Button {
                        guard let binding = ratingFilterBinding else { return }
                        if binding.wrappedValue.contains(stars) {
                            binding.wrappedValue.remove(stars)
                        } else {
                            binding.wrappedValue.insert(stars)
                        }
                        if let enabledBinding = ratingFilterEnabledBinding, !binding.wrappedValue.isEmpty {
                            enabledBinding.wrappedValue = true
                        }
                    } label: {
                        HStack {
                            Text(String(repeating: "\u{2605}", count: stars))
                            if ratingFilterBinding?.wrappedValue.contains(stars) ?? false {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Button {
                    guard let binding = ratingFilterBinding else { return }
                    if binding.wrappedValue.contains(0) {
                        binding.wrappedValue.remove(0)
                    } else {
                        binding.wrappedValue.insert(0)
                    }
                    if let enabledBinding = ratingFilterEnabledBinding, !binding.wrappedValue.isEmpty {
                        enabledBinding.wrappedValue = true
                    }
                } label: {
                    HStack {
                        Text("No Rating")
                        if ratingFilterBinding?.wrappedValue.contains(0) ?? false {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                Button {
                    ratingFilterEnabledBinding?.wrappedValue = true
                } label: {
                    HStack {
                        Text("Filter Enabled")
                        if ratingFilterEnabledBinding?.wrappedValue ?? false {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    ratingFilterEnabledBinding?.wrappedValue = false
                } label: {
                    HStack {
                        Text("Filter Disabled")
                        if !(ratingFilterEnabledBinding?.wrappedValue ?? true) {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Menu("Tags") {
                if let allTags, let tagFilterBinding {
                    Button {
                        tagFilterBinding.wrappedValue = []
                    } label: {
                        HStack {
                            Text("All")
                            if tagFilterBinding.wrappedValue.isEmpty {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            if tagFilterBinding.wrappedValue.contains(tag) {
                                tagFilterBinding.wrappedValue.remove(tag)
                            } else {
                                tagFilterBinding.wrappedValue.insert(tag)
                            }
                        } label: {
                            HStack {
                                Text(tag)
                                if tagFilterBinding.wrappedValue.contains(tag) {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            if let subtitleFilterBinding {
                Toggle("Has Transcript", isOn: subtitleFilterBinding)
            } else {
                Toggle("Has Transcript", isOn: .constant(false))
                    .disabled(true)
            }

            if let captionFilterBinding {
                Toggle("Has Caption", isOn: captionFilterBinding)
            } else {
                Toggle("Has Caption", isOn: .constant(false))
                    .disabled(true)
            }

            Divider()

            Menu("Sort By") {
                if let sortOrderBinding {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrderBinding.wrappedValue = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrderBinding.wrappedValue == order {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    if let sortAscendingBinding {
                        Toggle("Ascending", isOn: sortAscendingBinding)
                    }
                }
            }

            Divider()

            Button("Advanced Filter\u{2026}") {
                showAdvancedFilter?()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Divider()

            Button("Clear All Filters") {
                clearAllFilters?()
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }

    // MARK: - Slideshow Menu

    private var slideshowCommands: some Commands {
        CommandMenu("Slideshow") {
            Button("Start Slideshow") {
                startSlideshow?()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Divider()

            if let loopSlideshow {
                Toggle("Loop", isOn: loopSlideshow)
            }

            if let shuffleSlideshow {
                Toggle("Shuffle", isOn: shuffleSlideshow)
            }

            Divider()

            Menu("Transition") {
                if let slideshowTransition {
                    ForEach(TransitionType.allCases, id: \.self) { transition in
                        Button {
                            slideshowTransition.wrappedValue = transition
                        } label: {
                            HStack {
                                Text(transition.displayName)
                                if slideshowTransition.wrappedValue == transition {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subtitles Menu

    private var subtitleCommands: some Commands {
        CommandMenu("Subtitles") {
            if let subtitleShow {
                Toggle("Show Subtitles", isOn: subtitleShow)
            } else {
                Toggle("Show Subtitles", isOn: .constant(false))
                    .disabled(true)
            }

            Divider()

            Menu("Position") {
                if let subtitlePosition {
                    ForEach(CaptionPosition.allCases, id: \.self) { pos in
                        Button {
                            subtitlePosition.wrappedValue = pos
                        } label: {
                            HStack {
                                Text(pos.menuLabel)
                                if subtitlePosition.wrappedValue == pos {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Menu("Font Size") {
                if let subtitleFontSize {
                    ForEach(SubtitleFontSizeOption.allCases) { option in
                        Button {
                            subtitleFontSize.wrappedValue = option.size
                        } label: {
                            HStack {
                                Text(option.label)
                                if subtitleFontSize.wrappedValue == option.size {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Menu("Opacity") {
                if let subtitleOpacity {
                    ForEach(SubtitleOpacityOption.allCases) { option in
                        Button {
                            subtitleOpacity.wrappedValue = option.value
                        } label: {
                            HStack {
                                Text(option.label)
                                if subtitleOpacity.wrappedValue == option.value {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
