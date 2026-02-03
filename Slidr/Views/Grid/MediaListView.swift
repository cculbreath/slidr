import SwiftUI

struct MediaListView: View {
    @Bindable var viewModel: GridViewModel
    let items: [MediaItem]
    let onStartSlideshow: ([MediaItem], Int, Double?) -> Void
    var onQuickLook: ((MediaItem) -> Void)?
    var activePlaylist: Playlist?

    @Environment(MediaLibrary.self) private var library
    @Environment(PlaylistService.self) private var playlistService
    @SceneStorage("listColumnCustomization") private var columnCustomization: TableColumnCustomization<MediaItem>

    private var displayedItems: [MediaItem] { viewModel.filteredItems(items) }

    var body: some View {
        Table(displayedItems, selection: $viewModel.selectedItems, columnCustomization: $columnCustomization) {
            Group {
                TableColumn("") { (item: MediaItem) in
                    ListThumbnail(item: item, library: library)
                }
                .width(40)
                .customizationID(ListColumnID.thumbnail.rawValue)
                .disabledCustomizationBehavior(.all)

                TableColumn("Title", value: \.displayName)
                    .customizationID(ListColumnID.title.rawValue)

                TableColumn("Filename", value: \.originalFilename)
                    .customizationID(ListColumnID.filename.rawValue)
                    .defaultVisibility(.hidden)

                TableColumn("Media Type") { (item: MediaItem) in
                    Text(item.mediaType.rawValue.capitalized)
                }
                .customizationID(ListColumnID.mediaType.rawValue)

                TableColumn("Tags") { (item: MediaItem) in
                    Text(item.tags.joined(separator: ", "))
                        .lineLimit(1)
                }
                .customizationID(ListColumnID.tags.rawValue)

                TableColumn("Caption") { (item: MediaItem) in
                    Text(item.caption ?? "")
                        .lineLimit(1)
                }
                .customizationID(ListColumnID.caption.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Transcript") { (item: MediaItem) in
                    if item.hasTranscript {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(ideal: 70)
                .customizationID(ListColumnID.hasTranscript.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Summary") { (item: MediaItem) in
                    Text(item.summary ?? "")
                        .lineLimit(1)
                }
                .customizationID(ListColumnID.summary.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Duration") { (item: MediaItem) in
                    Text(item.formattedDuration ?? "")
                }
                .width(ideal: 60)
                .customizationID(ListColumnID.duration.rawValue)

                TableColumn("File Size") { (item: MediaItem) in
                    Text(formattedFileSize(item.fileSize))
                }
                .width(ideal: 80)
                .customizationID(ListColumnID.fileSize.rawValue)
            }

            Group {
                TableColumn("Date Imported") { (item: MediaItem) in
                    Text(item.importDate, style: .date)
                }
                .customizationID(ListColumnID.dateImported.rawValue)

                TableColumn("Date Modified") { (item: MediaItem) in
                    Text(item.fileModifiedDate, style: .date)
                }
                .customizationID(ListColumnID.dateModified.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Rating") { (item: MediaItem) in
                    if let rating = item.rating, rating > 0 {
                        Text(String(repeating: "\u{2605}", count: rating))
                            .foregroundStyle(.orange)
                    }
                }
                .width(ideal: 80)
                .customizationID(ListColumnID.rating.rawValue)

                TableColumn("Production") { (item: MediaItem) in
                    if let production = item.production {
                        Label(production.displayName, systemImage: production.iconName)
                    }
                }
                .customizationID(ListColumnID.production.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Source") { (item: MediaItem) in
                    Text(item.source ?? "")
                        .lineLimit(1)
                }
                .customizationID(ListColumnID.source.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Dimensions") { (item: MediaItem) in
                    if let w = item.width, let h = item.height {
                        Text("\(w) \u{00D7} \(h)")
                    }
                }
                .width(ideal: 90)
                .customizationID(ListColumnID.dimensions.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Frame Rate") { (item: MediaItem) in
                    if let fps = item.frameRate {
                        Text(String(format: "%.1f fps", fps))
                    }
                }
                .width(ideal: 80)
                .customizationID(ListColumnID.frameRate.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Audio") { (item: MediaItem) in
                    if let hasAudio = item.hasAudio {
                        Image(systemName: hasAudio ? "speaker.wave.2" : "speaker.slash")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(ideal: 50)
                .customizationID(ListColumnID.hasAudio.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Frames") { (item: MediaItem) in
                    if let count = item.frameCount {
                        Text("\(count)")
                    }
                }
                .width(ideal: 60)
                .customizationID(ListColumnID.frameCount.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Fav") { (item: MediaItem) in
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
                .width(ideal: 40)
                .customizationID(ListColumnID.favorite.rawValue)
                .defaultVisibility(.hidden)
            }

            Group {
                TableColumn("Storage") { (item: MediaItem) in
                    Label(item.storageLocation.displayName, systemImage: item.storageLocation.icon)
                }
                .customizationID(ListColumnID.storageLocation.rawValue)
                .defaultVisibility(.hidden)

                TableColumn("Status") { (item: MediaItem) in
                    Text(item.status.rawValue.capitalized)
                }
                .width(ideal: 70)
                .customizationID(ListColumnID.status.rawValue)
                .defaultVisibility(.hidden)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            contextMenuContent(for: selectedIDs)
        } primaryAction: { selectedIDs in
            guard let firstID = selectedIDs.first,
                  let index = displayedItems.firstIndex(where: { $0.id == firstID }) else { return }
            onStartSlideshow(displayedItems, index, nil)
        }
        .focusedSceneValue(\.listColumnCustomization, $columnCustomization)
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

// MARK: - List Thumbnail

/// Lightweight thumbnail for table rows that takes library explicitly
/// instead of using @Environment, which crashes during Table column resize.
private struct ListThumbnail: View {
    let item: MediaItem
    let library: MediaLibrary
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: item.id) {
            image = try? await library.thumbnail(for: item, size: .small)
        }
    }
}
