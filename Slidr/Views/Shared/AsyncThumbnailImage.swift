import SwiftUI

struct AsyncThumbnailImage: View {
    let item: MediaItem
    let size: ThumbnailSize
    var contentMode: ContentMode = .fill

    @Environment(MediaLibrary.self) private var library
    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var loadError: Error?

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
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        isLoading = true
        loadError = nil

        do {
            image = try await library.thumbnail(for: item, size: size)
        } catch {
            loadError = error
        }

        isLoading = false
    }
}
