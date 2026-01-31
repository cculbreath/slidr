import Foundation
import OSLog

struct TranscriptSearchResult: Identifiable {
    let id = UUID()
    let mediaItem: MediaItem
    let cue: TranscriptCue
    let contextSnippet: String
}

@MainActor
@Observable
final class TranscriptSearchService {
    var results: [TranscriptSearchResult] = []
    var isSearching = false
    var isPopupVisible = false

    private var transcriptStore: TranscriptStore?
    private var searchTask: Task<Void, Never>?

    func configure(transcriptStore: TranscriptStore?) {
        self.transcriptStore = transcriptStore
    }

    func search(query: String, in items: [MediaItem]) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let found = await performSearch(query: trimmed, items: items)

            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
            isPopupVisible = !found.isEmpty
        }
    }

    func clearResults() {
        searchTask?.cancel()
        results = []
        isSearching = false
        isPopupVisible = false
    }

    // MARK: - Private

    private func performSearch(query: String, items: [MediaItem]) async -> [TranscriptSearchResult] {
        guard let store = transcriptStore else { return [] }

        let queryLower = query.lowercased()
        let transcriptItems = items.filter { $0.hasTranscript }.prefix(20)

        var found: [TranscriptSearchResult] = []

        for item in transcriptItems {
            guard !Task.isCancelled else { return [] }

            // Quick check: does the plain text even contain the query?
            guard let plainText = item.transcriptText?.lowercased(),
                  plainText.contains(queryLower),
                  let relativePath = item.transcriptRelativePath else { continue }

            let cues: [TranscriptCue]
            do {
                cues = try await store.cues(forContentHash: item.contentHash, relativePath: relativePath)
            } catch {
                continue
            }

            var cueMatches = 0
            for cue in cues {
                guard cueMatches < 3, found.count < 15 else { break }

                let stripped = stripHTMLTags(cue.text)
                guard stripped.lowercased().contains(queryLower) else { continue }

                let snippet = truncateSnippet(stripped, maxLength: 120)
                found.append(TranscriptSearchResult(mediaItem: item, cue: cue, contextSnippet: snippet))
                cueMatches += 1
            }

            if found.count >= 15 { break }
        }

        return found
    }

    private func stripHTMLTags(_ string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private func truncateSnippet(_ text: String, maxLength: Int) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ")
        if cleaned.count <= maxLength { return cleaned }
        let endIndex = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
        return String(cleaned[..<endIndex]) + "…"
    }
}
