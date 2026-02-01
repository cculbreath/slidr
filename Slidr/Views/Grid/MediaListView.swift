import SwiftUI

struct MediaListView: View {
    @Bindable var viewModel: GridViewModel
    let items: [MediaItem]
    let onStartSlideshow: ([MediaItem], Int) -> Void
    var onQuickLook: ((MediaItem) -> Void)?
    var activePlaylist: Playlist?

    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @SceneStorage("listColumnCustomization") private var columnCustomization: TableColumnCustomization<MediaItem>

    private var displayedItems: [MediaItem] { viewModel.filteredItems(items) }

    var body: some View {
        Table(displayedItems, selection: $viewModel.selectedItems, columnCustomization: $columnCustomization) {
            TableColumn("") { item in
                AsyncThumbnailImage(item: item, size: .small)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .width(40)
            .customizationID(ListColumnID.thumbnail.rawValue)
            .disabledCustomization()

            TableColumn("Title", value: \.displayName)
                .customizationID(ListColumnID.title.rawValue)

            TableColumn("Filename", value: \.originalFilename)
                .customizationID(ListColumnID.filename.rawValue)
                .defaultVisibility(.hidden)

            TableColumn("Media Type") { item in
                Text(item.mediaType.rawValue.capitalized)
            }
            .customizationID(ListColumnID.mediaType.rawValue)

            TableColumn("Tags") { item in
                Text(item.tags.joined(separator: ", "))
                    .lineLimit(1)
            }
            .customizationID(ListColumnID.tags.rawValue)

            TableColumn("Caption") { item in
                Text(item.caption ?? "")
                    .lineLimit(1)
            }
            .customizationID(ListColumnID.caption.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Transcript") { item in
                Image(systemName: item.hasTranscript ? "checkmark" : "")
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 70)
            .customizationID(ListColumnID.hasTranscript.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Summary") { item in
                Text(item.summary ?? "")
                    .lineLimit(1)
            }
            .customizationID(ListColumnID.summary.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Duration") { item in
                Text(item.formattedDuration ?? "")
            }
            .width(ideal: 60)
            .customizationID(ListColumnID.duration.rawValue)

            TableColumn("File Size") { item in
                Text(formattedFileSize(item.fileSize))
            }
            .width(ideal: 80)
            .customizationID(ListColumnID.fileSize.rawValue)

            TableColumn("Date Imported") { item in
                Text(item.importDate, style: .date)
            }
            .customizationID(ListColumnID.dateImported.rawValue)

            TableColumn("Date Modified") { item in
                Text(item.fileModifiedDate, style: .date)
            }
            .customizationID(ListColumnID.dateModified.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Rating") { item in
                if let rating = item.rating, rating > 0 {
                    Text(String(repeating: "\u{2605}", count: rating))
                        .foregroundStyle(.orange)
                }
            }
            .width(ideal: 80)
            .customizationID(ListColumnID.rating.rawValue)

            TableColumn("Production") { item in
                if let production = item.production {
                    Label(production.displayName, systemImage: production.iconName)
                }
            }
            .customizationID(ListColumnID.production.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Source") { item in
                Text(item.source ?? "")
                    .lineLimit(1)
            }
            .customizationID(ListColumnID.source.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Dimensions") { item in
                if let w = item.width, let h = item.height {
                    Text("\(w) \u{00D7} \(h)")
                }
            }
            .width(ideal: 90)
            .customizationID(ListColumnID.dimensions.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Frame Rate") { item in
                if let fps = item.frameRate {
                    Text(String(format: "%.1f fps", fps))
                }
            }
            .width(ideal: 80)
            .customizationID(ListColumnID.frameRate.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Audio") { item in
                if let hasAudio = item.hasAudio {
                    Image(systemName: hasAudio ? "speaker.wave.2" : "speaker.slash")
                        .foregroundStyle(.secondary)
                }
            }
            .width(ideal: 50)
            .customizationID(ListColumnID.hasAudio.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Frames") { item in
                if let count = item.frameCount {
                    Text("\(count)")
                }
            }
            .width(ideal: 60)
            .customizationID(ListColumnID.frameCount.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Fav") { item in
                Image(systemName: item.isFavorite ? "heart.fill" : "")
                    .foregroundStyle(.red)
            }
            .width(ideal: 40)
            .customizationID(ListColumnID.favorite.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Storage") { item in
                Label(item.storageLocation.displayName, systemImage: item.storageLocation.icon)
            }
            .customizationID(ListColumnID.storageLocation.rawValue)
            .defaultVisibility(.hidden)

            TableColumn("Status") { item in
                Text(item.status.rawValue.capitalized)
            }
            .width(ideal: 70)
            .customizationID(ListColumnID.status.rawValue)
            .defaultVisibility(.hidden)
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            contextMenuContent(for: selectedIDs)
        } primaryAction: { selectedIDs in
            guard let firstID = selectedIDs.first,
                  let index = displayedItems.firstIndex(where: { $0.id == firstID }) else { return }
            onStartSlideshow(displayedItems, index)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuContent(for selectedIDs: Set<UUID>) -> some View {
        if let firstID = selectedIDs.first,
           let item = displayedItems.first(where: { $0.id == firstID }) {
            Button("Show in Finder") { showInFinder(item) }

            if item.storageLocation == .referenced {
                Button("Copy to Library") { copyToLibrary(item) }
            }

            if let playlist = activePlaylist, playlist.isManualPlaylist {
                Button("Remove from Playlist") {
                    for id in selectedIDs {
                        if let item = displayedItems.first(where: { $0.id == id }) {
                            playlistService.removeItem(item, from: playlist)
                        }
                    }
                }
            }

            Divider()

            Button("Move to Trash", role: .destructive) {
                let items = displayedItems.filter { selectedIDs.contains($0.id) }
                library.delete(items)
                viewModel.clearSelection()
            }
        }
    }

    // MARK: - Actions

    private func showInFinder(_ item: MediaItem) {
        let url = library.absoluteURL(for: item)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func copyToLibrary(_ item: MediaItem) {
        Task { try? await library.copyToLibrary(item) }
    }

    // MARK: - Formatting

    private func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
