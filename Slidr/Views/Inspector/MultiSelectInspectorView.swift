import SwiftUI
import SwiftData

struct MultiSelectInspectorView: View {
    let items: [MediaItem]
    let library: MediaLibrary
    let playlistService: PlaylistService

    @State private var newTag: String = ""
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                summarySection

                Divider()

                // Batch Actions
                batchActionsSection

                Divider()

                // Tag section
                tagSection

                Divider()

                // Playlist section
//                playlistSection

                Divider()

                // Delete
                deleteSection
            }
            .padding()
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 350)
        .confirmationDialog(
            "Move \(items.count) items to Trash?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move \(items.count) Items to Trash", role: .destructive) {
                library.delete(items)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(items.count) items will be moved to the Trash.")
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(items.count) items selected")
                .font(.headline)

            Text(totalSizeFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(mediaBreakdown)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var totalSizeFormatted: String {
        let total = items.reduce(Int64(0)) { $0 + $1.fileSize }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "Total: \(formatter.string(fromByteCount: total))"
    }

    private var mediaBreakdown: String {
        let images = items.filter { $0.mediaType == .image }.count
        let gifs = items.filter { $0.mediaType == .gif }.count
        let videos = items.filter { $0.mediaType == .video }.count

        var parts: [String] = []
        if images > 0 { parts.append("\(images) image\(images == 1 ? "" : "s")") }
        if gifs > 0 { parts.append("\(gifs) GIF\(gifs == 1 ? "" : "s")") }
        if videos > 0 { parts.append("\(videos) video\(videos == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Batch Actions

    private var batchActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Actions")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // Favorite toggle
            HStack {
                Button {
                    items.forEach { $0.isFavorite = true }
                } label: {
                    Label("Favorite All", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.pink)

                Button {
                    items.forEach { $0.isFavorite = false }
                } label: {
                    Label("Unfavorite All", systemImage: "heart.slash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)

            // Rating picker
            HStack {
                Text("Set Rating:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        items.forEach { $0.rating = rating }
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.yellow)
                }
                Button {
                    items.forEach { $0.rating = nil }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear rating")
            }
        }
    }

    // MARK: - Tag Section

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Tag")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Tag name", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addTagToAll()
                    }

                Button("Add") {
                    addTagToAll()
                }
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTagToAll() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        items.forEach { $0.addTag(tag) }
        newTag = ""
    }

    // MARK: - Playlist Section

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to Playlist")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            let manualPlaylists = playlistService.playlists.filter { $0.isManualPlaylist }
            if manualPlaylists.isEmpty {
                Text("No playlists available")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(manualPlaylists) { playlist in
                    Button {
                        playlistService.addItems(items, to: playlist)
                    } label: {
                        Label(playlist.name, systemImage: "music.note.list")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Label("Move \(items.count) Items to Trash", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
