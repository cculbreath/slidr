import SwiftUI

struct FileInfoSection: View {
    let item: MediaItem
    let library: MediaLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Information")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // File path
            InfoRow(label: "Location") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationLabel)
                        .font(.caption)
                        .foregroundStyle(locationColor)

                    Text(filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }

            // File size
            InfoRow(label: "Size", value: formattedSize)

            // Dimensions
            if let width = item.width, let height = item.height {
                InfoRow(label: "Dimensions", value: "\(width) x \(height)")
            }

            // Duration (for video)
            if let duration = item.formattedDuration {
                InfoRow(label: "Duration", value: duration)
            }

            // Frame rate (for video)
            if let frameRate = item.frameRate {
                InfoRow(label: "Frame Rate", value: String(format: "%.2f fps", frameRate))
            }

            // Frame count (for GIFs)
            if let frameCount = item.frameCount {
                InfoRow(label: "Frames", value: "\(frameCount)")
            }

            // Has audio (for video)
            if item.isVideo {
                InfoRow(label: "Audio", value: item.hasAudio == true ? "Yes" : "No")
            }

            Divider()

            // Dates
            InfoRow(label: "Imported", value: formattedDate(item.importDate))
            InfoRow(label: "Modified", value: formattedDate(item.fileModifiedDate))

            // Content hash
            InfoRow(label: "Hash") {
                Text(item.contentHash.prefix(16) + "...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Computed Properties

    private var filePath: String {
        let url = library.absoluteURL(for: item)
        return url.path
    }

    private var locationLabel: String {
        switch item.storageLocation {
        case .local: return "In Library"
        case .external: return "External Drive"
        case .referenced: return "Referenced"
        }
    }

    private var locationColor: Color {
        switch item.storageLocation {
        case .local: return .green
        case .external: return .orange
        case .referenced: return .blue
        }
    }

    private var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: item.fileSize)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Info Row

struct InfoRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            content
        }
    }
}

extension InfoRow where Content == Text {
    init(label: String, value: String) {
        self.label = label
        self.content = Text(value)
            .font(.caption)
    }
}
