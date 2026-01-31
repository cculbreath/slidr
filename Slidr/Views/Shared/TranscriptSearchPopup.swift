import SwiftUI

struct TranscriptSearchPopup: View {
    let results: [TranscriptSearchResult]
    let query: String
    let onSelect: (TranscriptSearchResult) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Transcript Matches")
                    .font(.headline)
                Text("\(results.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { result in
                        TranscriptSearchResultRow(result: result, query: query)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(result) }
                            .onHover { hovering in
                                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                            }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 380)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }
}

struct TranscriptSearchResultRow: View {
    let result: TranscriptSearchResult
    let query: String

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.mediaItem.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text("[\(formatTimestamp(result.cue.startTime))]")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }

            Text(highlightedSnippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var highlightedSnippet: AttributedString {
        var attributed = AttributedString(result.contextSnippet)
        let snippetLower = result.contextSnippet.lowercased()
        let queryLower = query.lowercased()

        var searchStart = snippetLower.startIndex
        while let range = snippetLower.range(of: queryLower, range: searchStart..<snippetLower.endIndex) {
            let attrStart = AttributedString.Index(range.lowerBound, within: attributed)
            let attrEnd = AttributedString.Index(range.upperBound, within: attributed)
            if let attrStart, let attrEnd {
                attributed[attrStart..<attrEnd].font = .caption.bold()
                attributed[attrStart..<attrEnd].foregroundColor = .primary
            }
            searchStart = range.upperBound
        }

        return attributed
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
