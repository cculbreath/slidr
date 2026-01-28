import SwiftUI

struct InfoOverlayView: View {
    @Bindable var item: MediaItem
    let index: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Info")
                    .font(.headline)
                Spacer()
                Text("\(index + 1) of \(totalCount)")
                    .foregroundStyle(.secondary)
            }

            Divider()

            SlideshowInfoRow(label: "Name", value: item.originalFilename)
            SlideshowInfoRow(label: "Type", value: item.mediaType.rawValue.capitalized)

            if let width = item.width, let height = item.height {
                SlideshowInfoRow(label: "Dimensions", value: "\(width) \u{00D7} \(height)")
            }

            if item.isVideo, let duration = item.duration {
                SlideshowInfoRow(label: "Duration", value: formatDuration(duration))
            }

            SlideshowInfoRow(label: "Size", value: formattedSize)

            if item.isRated {
                SlideshowInfoRow(label: "Rating", value: item.ratingStars)
            }

            if !item.tags.isEmpty {
                SlideshowInfoRow(label: "Tags", value: item.tags.joined(separator: ", "))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Caption")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Add caption...", text: Binding(
                    get: { item.caption ?? "" },
                    set: { item.caption = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Divider()

            SlideshowInfoRow(label: "Imported", value: formattedDate(item.importDate))
        }
        .padding()
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct SlideshowInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.body)
                .lineLimit(2)
            Spacer()
        }
    }
}
