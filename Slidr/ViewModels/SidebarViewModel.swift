import SwiftUI

@MainActor
@Observable
final class SidebarViewModel {
    // MARK: - State
    var selectedItem: SidebarItem? = .allMedia
    var isCreatingPlaylist = false
    var newPlaylistName = ""
    var newPlaylistType: PlaylistType = .manual
    var playlistToDelete: Playlist?
    var showDeleteConfirmation = false

    // MARK: - Dependencies
    private var playlistService: PlaylistService?

    // MARK: - Setup

    func configure(with service: PlaylistService) {
        self.playlistService = service
    }

    // MARK: - Computed Properties

    var playlists: [Playlist] {
        playlistService?.playlists ?? []
    }

    var manualPlaylists: [Playlist] {
        playlists.filter { $0.isManualPlaylist }
    }

    var smartPlaylists: [Playlist] {
        playlists.filter { $0.isSmartPlaylist }
    }

    // MARK: - Actions

    func createPlaylist() {
        guard let service = playlistService,
              !newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let playlist = service.createPlaylist(name: newPlaylistName, type: newPlaylistType)
        selectedItem = .playlist(playlist.id)

        // Reset state
        newPlaylistName = ""
        newPlaylistType = .manual
        isCreatingPlaylist = false
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlistToDelete = playlist
        showDeleteConfirmation = true
    }

    func confirmDelete() {
        guard let playlist = playlistToDelete,
              let service = playlistService else { return }

        // If deleting the selected playlist, go back to All Media
        if case .playlist(let id) = selectedItem, id == playlist.id {
            selectedItem = .allMedia
        }

        service.deletePlaylist(playlist)
        playlistToDelete = nil
        showDeleteConfirmation = false
    }

    func cancelDelete() {
        playlistToDelete = nil
        showDeleteConfirmation = false
    }
}
