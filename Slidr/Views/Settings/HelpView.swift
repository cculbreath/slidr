import SwiftUI

struct HelpView: View {
    @State private var selectedSection: HelpSection = .overview

    var body: some View {
        NavigationSplitView {
            List(HelpSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            ScrollView {
                selectedSection.content
                    .padding()
            }
            .frame(minWidth: 400)
        }
        .frame(width: 650, height: 500)
    }
}

// MARK: - Help Sections

enum HelpSection: String, CaseIterable, Identifiable {
    case overview
    case importing
    case organizing
    case slideshow
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .importing: return "Importing Media"
        case .organizing: return "Organizing"
        case .slideshow: return "Slideshow"
        case .shortcuts: return "Keyboard Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "info.circle"
        case .importing: return "square.and.arrow.down"
        case .organizing: return "folder"
        case .slideshow: return "play.rectangle"
        case .shortcuts: return "keyboard"
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .overview:
            OverviewHelpContent()
        case .importing:
            ImportingHelpContent()
        case .organizing:
            OrganizingHelpContent()
        case .slideshow:
            SlideshowHelpContent()
        case .shortcuts:
            ShortcutsHelpContent()
        }
    }
}

// MARK: - Help Content Views

struct OverviewHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Slidr")
                .font(.title)
                .fontWeight(.bold)

            Text("Slidr is a native macOS application for browsing, organizing, and viewing your images, GIFs, and videos.")

            Text("Getting Started")
                .font(.headline)

            Text("1. Import your media using File \u{2192} Import or drag files into the window")
            Text("2. Organize media into playlists")
            Text("3. View in slideshow mode for full-screen viewing")
        }
    }
}

struct ImportingHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Importing Media")
                .font(.title)
                .fontWeight(.bold)

            Text("Slidr supports images (JPEG, PNG, HEIC), GIFs, and videos (MP4, MOV, M4V).")

            Text("Import Methods")
                .font(.headline)

            Text("\u{2022} Drag and drop files or folders onto the Slidr window")
            Text("\u{2022} Use File \u{2192} Import (\u{2318}I)")
            Text("\u{2022} Click the + button in the sidebar")

            Text("Duplicate Detection")
                .font(.headline)

            Text("Slidr automatically detects and skips duplicate files based on content, not filename.")
        }
    }
}

struct OrganizingHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Organizing Media")
                .font(.title)
                .fontWeight(.bold)

            Text("Manual Playlists")
                .font(.headline)

            Text("Create playlists to group related media. Drag items from the grid onto playlists in the sidebar.")

            Text("Smart Playlists")
                .font(.headline)

            Text("Smart playlists automatically include media based on criteria like folder location, media type, or duration.")

            Text("Filters")
                .font(.headline)

            Text("Each playlist can have filters applied to limit which items are shown.")
        }
    }
}

struct SlideshowHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Slideshow")
                .font(.title)
                .fontWeight(.bold)

            Text("View your media in full-screen slideshow mode with automatic advancement.")

            Text("Starting a Slideshow")
                .font(.headline)

            Text("\u{2022} Double-click any item in the grid")
            Text("\u{2022} Select items and press \u{2318}\u{21E7}F")
            Text("\u{2022} Click the slideshow button in the toolbar")

            Text("Controls")
                .font(.headline)

            Text("Move your mouse to reveal controls. Use keyboard shortcuts for quick navigation.")
        }
    }
}

struct ShortcutsHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.title)
                .fontWeight(.bold)

            ShortcutSection(title: "General", shortcuts: [
                ("\u{2318},", "Open Settings"),
                ("\u{2318}I", "Import Files"),
                ("\u{2318}\u{21E7}F", "Start Slideshow"),
            ])

            ShortcutSection(title: "Grid", shortcuts: [
                ("\u{2318}A", "Select All"),
                ("Delete", "Delete Selected"),
                ("Space", "Quick Look"),
            ])

            ShortcutSection(title: "Slideshow", shortcuts: [
                ("Space", "Play/Pause"),
                ("\u{2190} \u{2192}", "Previous/Next"),
                ("\u{21E7}\u{2190} \u{21E7}\u{2192}", "Seek \u{00B1}5 seconds"),
                ("\u{2325}\u{2190} \u{2325}\u{2192}", "Seek \u{00B1}10 seconds"),
                (", .", "Frame Step"),
                ("\u{2191} \u{2193}", "Volume"),
                ("M", "Mute"),
                ("C", "Toggle Captions"),
                ("Escape", "Exit"),
            ])
        }
    }
}

// MARK: - Shortcut Section

struct ShortcutSection: View {
    let title: String
    let shortcuts: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(shortcuts, id: \.0) { shortcut in
                HStack {
                    Text(shortcut.0)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80, alignment: .leading)
                    Text(shortcut.1)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, 8)
    }
}
