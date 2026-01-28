import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @Environment(\.openWindow) private var openWindow
    @Bindable var viewModel: SidebarViewModel

    @State private var playlistDropTargetID: UUID?

    var body: some View {
        List(selection: $viewModel.selectedItem) {
            librarySection
            manualPlaylistsSection
            smartPlaylistsSection
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .confirmationDialog(
            "Delete Playlist?",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(viewModel.playlistToDeleteName)\"?")
        }
        .onAppear {
            viewModel.configure(with: playlistService)
        }
    }

    // MARK: - Library Section

    private var librarySection: some View {
        Section("Library") {
            allMediaRow
            favoritesRow
            Label("Last Import", systemImage: "clock.arrow.circlepath")
                .tag(SidebarItem.lastImport)
            Label("Imported Today", systemImage: "calendar")
                .tag(SidebarItem.importedToday)
            unplayableVideosRow
        }
    }

    @ViewBuilder
    private var unplayableVideosRow: some View {
        let count = library.unplayableVideoCount
        if count > 0 {
            Label {
                HStack {
                    Text("Unplayable Videos")
                    Spacer()
                    Text("\(count)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            .tag(SidebarItem.unplayableVideos)
        }
    }

    private var allMediaRow: some View {
        Label {
            HStack {
                Text("All Media")
                Spacer()
                Text("\(library.itemCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "photo.on.rectangle.angled")
        }
        .tag(SidebarItem.allMedia)
    }

    private var favoritesRow: some View {
        Label {
            HStack {
                Text("Favorites")
                Spacer()
                Text("\(favoritesCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
        }
        .tag(SidebarItem.favorites)
    }

    // MARK: - Manual Playlists Section

    private var manualPlaylistsSection: some View {
        Section {
            ForEach(viewModel.manualPlaylists) { playlist in
                manualPlaylistRow(playlist: playlist)
            }
        } header: {
            HStack {
                Text("Playlists")
                Spacer()
                Button {
                    viewModel.createPlaylist()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private func manualPlaylistRow(playlist: Playlist) -> some View {
        Group {
            if viewModel.editingPlaylistID == playlist.id {
                inlinePlaylistEditor(playlist: playlist)
            } else {
                PlaylistRow(
                    playlist: playlist,
                    onEdit: { openWindow(value: playlist.id) },
                    onDelete: { viewModel.deletePlaylist(playlist) }
                )
            }
        }
        .tag(SidebarItem.playlist(playlist.id))
        .dropDestination(for: String.self) { uuidStrings, _ in
            // Each string may contain newline-separated UUIDs for multi-select drag
            let itemIDs = uuidStrings
                .flatMap { $0.components(separatedBy: "\n") }
                .compactMap { UUID(uuidString: $0) }
            return handleDrop(itemIDs: itemIDs, onto: playlist)
        } isTargeted: { targeted in
            playlistDropTargetID = targeted ? playlist.id : nil
        }
        .listRowBackground(
            playlistDropTargetID == playlist.id
                ? Color.accentColor.opacity(0.2)
                : nil
        )
    }

    // MARK: - Smart Playlists Section

    private var smartPlaylistsSection: some View {
        Section {
            ForEach(viewModel.smartPlaylists) { playlist in
                PlaylistRow(
                    playlist: playlist,
                    onEdit: { openWindow(value: playlist.id) },
                    onDelete: { viewModel.deletePlaylist(playlist) }
                )
                .tag(SidebarItem.playlist(playlist.id))
            }
        } header: {
            HStack {
                Text("Smart Playlists")
                Spacer()
                Button {
                    viewModel.createSmartPlaylist()
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 8)
        }
    }

    // MARK: - Inline Playlist Editor

    @ViewBuilder
    private func inlinePlaylistEditor(playlist: Playlist) -> some View {
        TextField("Playlist Name", text: Binding(
            get: { playlist.name },
            set: { playlist.name = $0 }
        ))
        .onSubmit {
            let trimmed = playlist.name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                viewModel.cancelInlineEdit(playlist: playlist)
            } else {
                viewModel.finishInlineEdit()
            }
        }
        .onExitCommand {
            let trimmed = playlist.name.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                viewModel.cancelInlineEdit(playlist: playlist)
            } else {
                viewModel.finishInlineEdit()
            }
        }
    }

    // MARK: - Computed Properties

    private var favoritesCount: Int {
        library.allItems.filter { $0.isFavorite }.count
    }

    // MARK: - Actions

    private func handleDrop(itemIDs: [UUID], onto playlist: Playlist) -> Bool {
        let items = library.allItems.filter { itemIDs.contains($0.id) }
        guard !items.isEmpty else { return false }

//        playlistService.addItems(items, to: playlist)
        return true
    }
}

// MARK: - SidebarItem

enum SidebarItem: Hashable, Identifiable {
    case allMedia
    case favorites
    case lastImport
    case importedToday
    case unplayableVideos
    case playlist(UUID)

    var id: String {
        switch self {
        case .allMedia: return "allMedia"
        case .favorites: return "favorites"
        case .lastImport: return "lastImport"
        case .importedToday: return "importedToday"
        case .unplayableVideos: return "unplayableVideos"
        case .playlist(let uuid): return "playlist-\(uuid.uuidString)"
        }
    }
}

// MARK: - Playlist Row

struct PlaylistRow: View {
    let playlist: Playlist
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Label {
            HStack {
                Text(playlist.name)
                Spacer()
                Text("\(itemCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
        }
        .contextMenu {
            Button("Edit Playlist...") {
                onEdit()
            }
            Divider()
            Button("Delete Playlist", role: .destructive) {
                onDelete()
            }
        }
    }

    private var itemCount: Int {
        if playlist.isManualPlaylist {
            return playlist.manualItemOrder.count
        }
        return 0
    }

    private var iconName: String {
        if let name = playlist.iconName {
            return name
        }
        return playlist.isSmartPlaylist ? "gearshape" : "music.note.list"
    }

    private var iconColor: Color {
        if let hex = playlist.colorHex {
            return Color(hex: hex) ?? .accentColor
        }
        return playlist.isSmartPlaylist ? .orange : .accentColor
    }
}
