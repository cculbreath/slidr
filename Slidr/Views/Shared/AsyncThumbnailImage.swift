import SwiftUI

struct AsyncThumbnailImage: View {
    private let source: Source
    let size: ThumbnailSize
    var contentMode: ContentMode = .fill

    @Environment(MediaLibrary.self) private var library
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var loadError: Error?

    enum Source {
        case live(MediaItem)
        case snapshot(MediaItemSnapshot)

        var id: UUID {
            switch self {
            case .live(let item): return item.id
            case .snapshot(let snapshot): return snapshot.id
            }
        }
    }

    init(item: MediaItem, size: ThumbnailSize, contentMode: ContentMode = .fill) {
        self.source = .live(item)
        self.size = size
        self.contentMode = contentMode
    }

    init(snapshot: MediaItemSnapshot, size: ThumbnailSize, contentMode: ContentMode = .fit) {
        self.source = .snapshot(snapshot)
        self.size = size
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.gray.opacity(0.1))
            }
        }
        .task(id: source.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        isLoading = true
        loadError = nil

        do {
            switch source {
            case .live(let item):
                image = try await library.thumbnail(for: item, size: size)
            case .snapshot(let snapshot):
                image = try await library.thumbnail(snapshot: snapshot, size: size)
            }
        } catch {
            loadError = error
            // Only the live-model variant can record a thumbnail-error flag — and
            // a disconnected external drive is transient, not a broken file, so
            // don't flag those or they'd stay marked unplayable after reconnect.
            if case .live(let item) = source, item.isVideo {
                if case LibraryError.externalDriveDisconnected = error {
                    // Transient: leave unflagged so it recovers on reconnect.
                } else {
                    item.hasThumbnailError = true
                }
            }
        }

        isLoading = false
    }
}
