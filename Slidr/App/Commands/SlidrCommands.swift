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

    // MARK: - Binding FocusedValues
    @FocusedValue(\.importDestination) var importDestination
    @FocusedValue(\.gridShowFilenames) var gridShowFilenames
    @FocusedValue(\.gridShowCaptions) var gridShowCaptions
    @FocusedValue(\.animateGIFs) var animateGIFs
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

    // MARK: - View Menu

    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
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

            Divider()

            if let gridShowFilenames {
                Toggle("Show Grid Filenames", isOn: gridShowFilenames)
            }

            if let gridShowCaptions {
                Toggle("Show Grid Captions", isOn: gridShowCaptions)
            }

            if let animateGIFs {
                Toggle("Animate GIFs in Grid", isOn: animateGIFs)
            }

            Divider()

            Button("Enter Fullscreen Slideshow") {
                startSlideshow?()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Divider()

            Button("Toggle Inspector") {
                toggleInspector?()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Reveal in Finder") {
                revealInFinder?()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
