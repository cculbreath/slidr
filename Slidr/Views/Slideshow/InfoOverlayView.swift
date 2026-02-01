import SwiftUI

struct InfoOverlayView: View {
    @Bindable var item: MediaItem
    let index: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Info")
                    .font(.headline)
                Spacer()
                Text("\(index + 1) of \(totalCount)")
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SlideshowInfoRow(label: "Name", value: item.originalFilename)
                    SlideshowInfoRow(label: "Type", value: item.mediaType.rawValue.capitalized)

                    if let width = item.width, let height = item.height {
                        SlideshowInfoRow(label: "Dimensions", value: "\(width) \u{00D7} \(height)")
                    }

                    if item.isVideo, let duration = item.duration {
                        SlideshowInfoRow(label: "Duration", value: formatDuration(duration))
                    }

                    SlideshowInfoRow(label: "Size", value: formattedSize)

                    EditableRatingRow(label: "Rating", rating: $item.rating)

                    EditableInfoRow(
                        label: "Tags",
                        value: item.tags.sorted().joined(separator: ", "),
                        placeholder: "Add tags...",
                        onSave: { newValue in
                            let tags = newValue.split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            item.tags = tags
                        }
                    )

                    EditableInfoRow(
                        label: "Summary",
                        value: item.summary ?? "",
                        placeholder: "Add summary...",
                        onSave: { newValue in
                            item.summary = newValue.isEmpty ? nil : newValue
                        }
                    )

                    EditableInfoRow(
                        label: "Caption",
                        value: item.caption ?? "",
                        placeholder: "Add caption...",
                        onSave: { newValue in
                            item.caption = newValue.isEmpty ? nil : newValue
                        }
                    )

                    Divider()

                    SlideshowInfoRow(label: "Imported", value: formattedDate(item.importDate))
                }
                .padding()
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    private var formattedSize: String {
        Formatters.formatFileSize(item.fileSize)
    }

    private func formattedDate(_ date: Date) -> String {
        Formatters.formatDate(date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Read-Only Row

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
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Editable Text Row

private struct EditableInfoRow: View {
    let label: String
    let value: String
    let placeholder: String
    let onSave: (String) -> Void

    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            if isEditing {
                VStack(alignment: .trailing, spacing: 4) {
                    TextField(placeholder, text: $editText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...10)

                    HStack(spacing: 8) {
                        Button {
                            isEditing = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")

                        Button {
                            onSave(editText)
                            isEditing = false
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Save")
                    }
                }
            } else {
                Group {
                    if value.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(value)
                            .textSelection(.enabled)
                    }
                }
                .font(.body)

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                editText = value
                isEditing = true
            }
        }
    }
}

// MARK: - Editable Rating Row

private struct EditableRatingRow: View {
    let label: String
    @Binding var rating: Int?

    @State private var isEditing = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            if isEditing {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                            .foregroundStyle(star <= (rating ?? 0) ? .yellow : .secondary)
                            .onTapGesture {
                                if rating == star {
                                    rating = nil
                                } else {
                                    rating = star
                                }
                            }
                    }

                    Spacer()

                    Button {
                        isEditing = false
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                if let rating, rating > 0 {
                    Text(String(repeating: "\u{2605}", count: rating))
                        .font(.body)
                } else {
                    Text("No rating")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                isEditing = true
            }
        }
    }
}
