import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @Bindable var viewModel: SidebarViewModel

    @State private var playlistToEdit: Playlist?

    var body: some View {
        List(selection: $viewModel.selectedItem) {
            // Library Section
            Section("Library") {
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

            // Playlists Section
            Section {
                ForEach(viewModel.manualPlaylists) { playlist in
                    PlaylistRow(
                        playlist: playlist,
                        onEdit: { playlistToEdit = playlist },
                        onDelete: { viewModel.deletePlaylist(playlist) }
                    )
                    .tag(SidebarItem.playlist(playlist.id))
                    .dropDestination(for: String.self) { uuidStrings, _ in
                        let itemIDs = uuidStrings.compactMap { UUID(uuidString: $0) }
                        return handleDrop(itemIDs: itemIDs, onto: playlist)
                    }
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button {
                        viewModel.newPlaylistType = .manual
                        viewModel.isCreatingPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Smart Playlists Section
            Section {
                ForEach(viewModel.smartPlaylists) { playlist in
                    PlaylistRow(
                        playlist: playlist,
                        onEdit: { playlistToEdit = playlist },
                        onDelete: { viewModel.deletePlaylist(playlist) }
                    )
                    .tag(SidebarItem.playlist(playlist.id))
                }
            } header: {
                HStack {
                    Text("Smart Playlists")
                    Spacer()
                    Button {
                        viewModel.newPlaylistType = .smart
                        viewModel.isCreatingPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button {
                    importFiles()
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isCreatingPlaylist) {
            CreatePlaylistSheet(viewModel: viewModel)
        }
        .sheet(item: $playlistToEdit) { playlist in
            PlaylistEditorView(playlist: playlist)
        }
        .confirmationDialog(
            "Delete Playlist",
            isPresented: $viewModel.showDeleteConfirmation,
            presenting: viewModel.playlistToDelete
        ) { playlist in
            Button("Delete \"\(playlist.name)\"", role: .destructive) {
                viewModel.confirmDelete()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: { playlist in
            Text("Are you sure you want to delete \"\(playlist.name)\"? This cannot be undone.")
        }
        .onAppear {
            viewModel.configure(with: playlistService)
        }
    }

    // MARK: - Computed Properties

    private var favoritesCount: Int {
        library.allItems.filter { $0.isFavorite }.count
    }

    // MARK: - Actions

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [
            .image, .gif, .movie, .video, .mpeg4Movie, .quickTimeMovie
        ]

        if panel.runModal() == .OK {
            Task {
                _ = try? await library.importFiles(urls: panel.urls)
            }
        }
    }

    private func handleDrop(itemIDs: [UUID], onto playlist: Playlist) -> Bool {
        let items = library.allItems.filter { itemIDs.contains($0.id) }
        guard !items.isEmpty else { return false }

        playlistService.addItems(items, to: playlist)
        return true
    }
}

// MARK: - SidebarItem

enum SidebarItem: Hashable, Identifiable {
    case allMedia
    case favorites
    case playlist(UUID)

    var id: String {
        switch self {
        case .allMedia: return "allMedia"
        case .favorites: return "favorites"
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

// MARK: - Create Playlist Sheet

struct CreatePlaylistSheet: View {
    @Bindable var viewModel: SidebarViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(viewModel.newPlaylistType == .smart ? "New Smart Playlist" : "New Playlist")
                .font(.headline)

            TextField("Playlist Name", text: $viewModel.newPlaylistName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack(spacing: 16) {
                Button("Cancel") {
                    viewModel.newPlaylistName = ""
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    viewModel.createPlaylist()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(viewModel.newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

