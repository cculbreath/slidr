import SwiftUI

@MainActor
@Observable
final class SidebarViewModel {
    // MARK: - State
    var selectedItem: SidebarItem? = .allMedia
    var editingPlaylistID: UUID?
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

    // MARK: - Inline Playlist Creation

    func createPlaylist() {
        guard let service = playlistService else { return }
        let playlist = service.createPlaylist(name: "New Playlist", type: .manual)
        editingPlaylistID = playlist.id
        selectedItem = .playlist(playlist.id)
    }

    func createSmartPlaylist() {
        guard let service = playlistService else { return }
        let playlist = service.createPlaylist(name: "New Smart Playlist", type: .smart)
        editingPlaylistID = playlist.id
        selectedItem = .playlist(playlist.id)
    }

    func finishInlineEdit() {
        guard let editingID = editingPlaylistID,
              let service = playlistService,
              let playlist = service.playlist(withID: editingID) else {
            editingPlaylistID = nil
            return
        }
        let trimmed = playlist.name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            service.deletePlaylist(playlist)
            selectedItem = .allMedia
        } else {
            service.updatePlaylist(playlist)
        }
        editingPlaylistID = nil
    }

    func cancelInlineEdit(playlist: Playlist) {
        guard let service = playlistService else { return }
        let trimmed = playlist.name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            service.deletePlaylist(playlist)
            selectedItem = .allMedia
        }
        editingPlaylistID = nil
    }

    // MARK: - Delete

    var playlistToDeleteName: String = ""

    func deletePlaylist(_ playlist: Playlist) {
        playlistToDelete = playlist
        playlistToDeleteName = playlist.name
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
        playlistToDeleteName = ""
        showDeleteConfirmation = false
    }

    func cancelDelete() {
        playlistToDelete = nil
        playlistToDeleteName = ""
        showDeleteConfirmation = false
    }
}
