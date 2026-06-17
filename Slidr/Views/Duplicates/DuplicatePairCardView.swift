import SwiftUI

/// One side of a duplicate pair: thumbnail/video, metadata, and a "Keep" button.
/// Consumes a `MediaItemSnapshot` rather than a `@Model MediaItem` so SwiftUI
/// re-renders that arrive after the user trashes the other side of the pair
/// can't access a tombstoned model.
struct DuplicatePairCardView: View {
    let snapshot: MediaItemSnapshot
    let label: String
    let keepShortcutHint: String
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HoverPlayingMediaView(snapshot: snapshot)
                .frame(height: 480)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            metadata
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onKeep()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Keep this — delete other")
                    Spacer()
                    Text(keepShortcutHint)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.filename)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack(spacing: 12) {
                metaChip(systemImage: "doc", text: Formatters.formatFileSize(snapshot.fileSize))
                if let dims = snapshot.dimensions {
                    metaChip(
                        systemImage: "aspectratio",
                        text: "\(Int(dims.width))\u{00d7}\(Int(dims.height))"
                    )
                }
                if let duration = snapshot.formattedDuration {
                    metaChip(systemImage: "timer", text: duration)
                }
            }

            HStack(spacing: 12) {
                if snapshot.isRated {
                    metaChip(systemImage: "star.fill", text: snapshot.ratingStars)
                }
                if snapshot.tagsCount > 0 {
                    metaChip(systemImage: "tag", text: "\(snapshot.tagsCount) tag\(snapshot.tagsCount == 1 ? "" : "s")")
                }
                metaChip(systemImage: "calendar", text: Formatters.longDate.string(from: snapshot.importDate))
            }
            .foregroundStyle(.secondary)
        }
    }

    private func metaChip(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }
}
