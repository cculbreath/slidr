import SwiftUI
import SwiftData

struct MediaInspectorView: View {
    @Bindable var item: MediaItem
    @Environment(MediaLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext

    @State private var isCopyingToLibrary = false
    @State private var showCopySuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Thumbnail preview
                thumbnailSection

                Divider()

                // Caption
                CaptionEditorView(caption: $item.caption)

                Divider()

                // File info
                FileInfoSection(item: item, library: library)

                Divider()

                // Actions
                actionsSection
            }
            .padding()
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 350)
    }

    // MARK: - Thumbnail Section

    private var thumbnailSection: some View {
        VStack(spacing: 8) {
            AsyncThumbnailImage(item: item, size: .large)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.originalFilename)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Type badge
            HStack {
                Image(systemName: typeIcon)
                Text(item.mediaType.rawValue.capitalized)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var typeIcon: String {
        switch item.mediaType {
        case .image: return "photo"
        case .gif: return "play.square.stack"
        case .video: return "film"
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Show in Finder
            Button {
                showInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // Copy to Library (only for referenced files)
            if item.storageLocation == .referenced {
                Button {
                    copyToLibrary()
                } label: {
                    if isCopyingToLibrary {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Copy to Library", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isCopyingToLibrary)

                if showCopySuccess {
                    Text("Copied to library")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Toggle favorite
            Button {
                item.isFavorite.toggle()
            } label: {
                Label(
                    item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: item.isFavorite ? "heart.fill" : "heart"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(item.isFavorite ? .pink : nil)
        }
    }

    // MARK: - Actions

    private func showInFinder() {
        let url = library.absoluteURL(for: item)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    private func copyToLibrary() {
        isCopyingToLibrary = true
        Task {
            do {
                try await library.copyToLibrary(item)
                showCopySuccess = true

                // Hide success message after delay
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                showCopySuccess = false
            } catch {
                // Error is already logged in MediaLibrary
            }
            isCopyingToLibrary = false
        }
    }
}
