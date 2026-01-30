import SwiftUI
import AppKit

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

    var body: some Commands {
        helpCommands
        pasteboardCommands
        searchCommands
        fileCommands
        viewCommands
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
