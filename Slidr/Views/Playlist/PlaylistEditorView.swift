import SwiftUI

struct PlaylistEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlaylistService.self) private var playlistService

    let playlist: Playlist
    let isNew: Bool

    @State private var name: String = ""
    @State private var iconName: String = "music.note.list"
    @State private var colorHex: String = ""
    @State private var sortOrder: SortOrder = .dateImported
    @State private var sortAscending: Bool = false

    // Smart playlist
    @State private var watchedFolderPath: String = ""
    @State private var includeSubfolders: Bool = true

    // Filters
    @State private var filterFavoritesOnly: Bool = false
    @State private var filterMinDuration: Double? = nil
    @State private var filterMaxDuration: Double? = nil
    @State private var filterImages: Bool = true
    @State private var filterVideos: Bool = true
    @State private var filterGIFs: Bool = true

    private let availableIcons = [
        "music.note.list", "folder.fill", "star.fill", "heart.fill",
        "film.fill", "photo.fill", "camera.fill", "wand.and.stars",
        "sparkles", "bolt.fill", "flame.fill", "leaf.fill",
    ]

    private let availableColors = [
        "",
        "FF6B6B", "4ECDC4", "45B7D1", "96CEB4",
        "FFEAA7", "DDA0DD", "98D8C8", "F7DC6F",
    ]

    init(playlist: Playlist, isNew: Bool = false) {
        self.playlist = playlist
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    basicInfoSection

                    appearanceSection

                    if playlist.isSmartPlaylist {
                        smartPlaylistSection
                    }

                    filtersSection

                    sortingSection
                }
                .padding(24)
            }

            Divider()

            footer
        }
        .frame(width: 450, height: 550)
        .onAppear {
            loadPlaylistData()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(isNew ? "New Playlist" : "Edit Playlist")
                .font(.headline)
            Spacer()
        }
        .padding()
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Info")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            TextField("Playlist Name", text: $name)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(36)), count: 6),
                    spacing: 8
                ) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button {
                            iconName = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 32, height: 32)
                                .background(
                                    iconName == icon
                                        ? Color.accentColor.opacity(0.2) : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(availableColors, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(
                                    hex.isEmpty
                                        ? Color.accentColor : (Color(hex: hex) ?? .gray)
                                )
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            colorHex == hex
                                                ? Color.primary : Color.clear, lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Smart Playlist Section

    private var smartPlaylistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watched Folder")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            FolderPickerView(
                folderPath: $watchedFolderPath,
                title: "Select Watched Folder",
                message: "Select a folder to watch for new media files"
            )

            Toggle("Include subfolders", isOn: $includeSubfolders)

            if !watchedFolderPath.isEmpty {
                Text(
                    "Files added to this folder will automatically appear in this playlist."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Filters Section

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Media Types")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Toggle("Images", isOn: $filterImages)
                    Toggle("Videos", isOn: $filterVideos)
                    Toggle("GIFs", isOn: $filterGIFs)
                }
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Duration (for videos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Min:")
                    TextField("", value: $filterMinDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("sec")

                    Spacer()
                        .frame(width: 24)

                    Text("Max:")
                    TextField("", value: $filterMaxDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("sec")
                }
            }

            Toggle("Favorites only", isOn: $filterFavoritesOnly)
        }
    }

    // MARK: - Sorting Section

    private var sortingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sorting")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack {
                Picker("Sort by", selection: $sortOrder) {
                    Text("Name").tag(SortOrder.name)
                    Text("Date Modified").tag(SortOrder.dateModified)
                    Text("Date Imported").tag(SortOrder.dateImported)
                    Text("File Size").tag(SortOrder.fileSize)
                }
                .frame(width: 180)

                Picker("Order", selection: $sortAscending) {
                    Text("Ascending").tag(true)
                    Text("Descending").tag(false)
                }
                .frame(width: 130)
            }

            if playlist.isManualPlaylist {
                Text(
                    "Manual playlists preserve custom order. Sorting is only applied for display."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Button(isNew ? "Create" : "Save") {
                savePlaylist()
                dismiss()
            }
            .keyboardShortcut(.return)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    // MARK: - Actions

    private func loadPlaylistData() {
        name = playlist.name
        iconName = playlist.iconName ?? "music.note.list"
        colorHex = playlist.colorHex ?? ""
        sortOrder = playlist.sortOrder
        sortAscending = playlist.sortAscending

        watchedFolderPath = playlist.watchedFolderPath ?? ""
        includeSubfolders = playlist.includeSubfolders

        filterFavoritesOnly = playlist.filterFavoritesOnly
        filterMinDuration = playlist.filterMinDuration
        filterMaxDuration = playlist.filterMaxDuration

        if let typeStrings = playlist.filterMediaTypes {
            let types = Set(typeStrings.compactMap { MediaType(rawValue: $0) })
            filterImages = types.contains(.image)
            filterVideos = types.contains(.video)
            filterGIFs = types.contains(.gif)
        } else {
            filterImages = true
            filterVideos = true
            filterGIFs = true
        }
    }

    private func savePlaylist() {
        playlist.name = name
        playlist.iconName = iconName
        playlist.colorHex = colorHex.isEmpty ? nil : colorHex
        playlist.sortOrder = sortOrder
        playlist.sortAscending = sortAscending

        playlist.includeSubfolders = includeSubfolders

        playlist.filterFavoritesOnly = filterFavoritesOnly
        playlist.filterMinDuration = filterMinDuration
        playlist.filterMaxDuration = filterMaxDuration

        var mediaTypes: [String] = []
        if filterImages { mediaTypes.append(MediaType.image.rawValue) }
        if filterVideos { mediaTypes.append(MediaType.video.rawValue) }
        if filterGIFs { mediaTypes.append(MediaType.gif.rawValue) }

        if mediaTypes.count == 3 {
            playlist.filterMediaTypes = nil
        } else {
            playlist.filterMediaTypes = mediaTypes
        }

        if playlist.isSmartPlaylist {
            let newURL = watchedFolderPath.isEmpty ? nil : URL(fileURLWithPath: watchedFolderPath)
            if newURL?.path != playlist.watchedFolderPath {
                playlistService.setWatchedFolder(newURL, for: playlist)
            }
        }

        playlistService.updatePlaylist(playlist)
    }
}
