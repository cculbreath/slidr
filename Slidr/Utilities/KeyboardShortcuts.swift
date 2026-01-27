import SwiftUI

enum KeyboardShortcuts {
    // MARK: - General
    static let openSettings = KeyboardShortcut(",", modifiers: .command)
    static let importFiles = KeyboardShortcut("i", modifiers: .command)

    // MARK: - Grid Navigation
    static let selectAll = KeyboardShortcut("a", modifiers: .command)
    static let deselectAll = KeyboardShortcut("a", modifiers: [.command, .shift])
    static let deleteSelected = KeyboardShortcut(.delete, modifiers: [])
    static let quickLook = KeyboardShortcut(.space, modifiers: [])
    static let startSlideshow = KeyboardShortcut(.return, modifiers: [])
    static let focusSearch = KeyboardShortcut("f", modifiers: .command)

    // MARK: - Thumbnails
    static let increaseThumbnailSize = KeyboardShortcut("+", modifiers: .command)
    static let decreaseThumbnailSize = KeyboardShortcut("-", modifiers: .command)

    // MARK: - Playlists
    static let newPlaylist = KeyboardShortcut("n", modifiers: .command)
    static let newSmartPlaylist = KeyboardShortcut("n", modifiers: [.command, .shift])

    // MARK: - Inspector
    static let toggleInspector = KeyboardShortcut("i", modifiers: .command)
    static let revealInFinder = KeyboardShortcut("r", modifiers: [.command, .shift])

    // MARK: - Slideshow Reference
    static let slideshowShortcuts: [(String, String)] = [
        ("Space", "Play/Pause"),
        ("\u{2190} / \u{2192}", "Previous / Next"),
        ("J / L", "Previous / Next (alt)"),
        ("\u{21E7}\u{2190} / \u{21E7}\u{2192}", "Seek \u{00B1}5 seconds"),
        ("\u{2325}\u{2190} / \u{2325}\u{2192}", "Seek \u{00B1}30 seconds"),
        (", / .", "Frame step"),
        ("\u{2191} / \u{2193}", "Volume up / down"),
        ("M", "Mute toggle"),
        ("C", "Toggle captions"),
        ("I", "Toggle info overlay"),
        ("R", "Toggle shuffle"),
        ("F", "Toggle fullscreen"),
        ("1-5", "Rate item (stars)"),
        ("0", "Clear rating"),
        ("Escape", "Exit slideshow"),
    ]

    // MARK: - Grid Reference
    static let gridShortcuts: [(String, String)] = [
        ("\u{2318}A", "Select all"),
        ("\u{2318}\u{21E7}A", "Deselect all"),
        ("Delete", "Delete selected"),
        ("Space", "Quick Look"),
        ("Enter", "Start slideshow"),
        ("\u{2318}F", "Focus search"),
        ("\u{2191}\u{2193}\u{2190}\u{2192}", "Navigate selection"),
        ("\u{2318}+", "Larger thumbnails"),
        ("\u{2318}-", "Smaller thumbnails"),
    ]

    // MARK: - General Reference
    static let generalShortcuts: [(String, String)] = [
        ("\u{2318},", "Settings"),
        ("\u{2318}I", "Import files"),
        ("\u{2318}\u{2325}I", "Toggle inspector"),
        ("\u{2318}N", "New playlist"),
        ("\u{2318}\u{21E7}N", "New smart playlist"),
        ("\u{2318}\u{21E7}R", "Reveal in Finder"),
    ]
}
