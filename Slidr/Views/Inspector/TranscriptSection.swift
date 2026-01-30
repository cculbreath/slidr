import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct TranscriptSection: View {
    @Bindable var item: MediaItem
    @Environment(\.transcriptStore) private var transcriptStore
    @Environment(\.modelContext) private var modelContext

    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcript")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if item.hasTranscript {
                transcriptInfo
            } else {
                importButton
            }

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var transcriptInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Format badge
            if let path = item.transcriptRelativePath {
                let ext = (path as NSString).pathExtension.uppercased()
                HStack {
                    Text(ext)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Spacer()
                }
            }

            // Preview text
            if let text = item.transcriptText {
                let preview = String(text.prefix(100))
                Text(preview + (text.count > 100 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Remove button
            Button(role: .destructive) {
                removeTranscript()
            } label: {
                Label("Remove Transcript", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var importButton: some View {
        Button {
            importTranscript()
        } label: {
            if isImporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Import SRT/VTT...", systemImage: "captions.bubble")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isImporting)
    }

    private func importTranscript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "vtt") ?? .plainText
        ]
        panel.message = "Select a subtitle file to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        importError = nil

        guard let transcriptStore else {
            isImporting = false
            return
        }

        Task {
            do {
                let result = try await transcriptStore.importTranscript(
                    from: url,
                    forContentHash: item.contentHash
                )
                item.transcriptText = result.plainText
                item.transcriptRelativePath = result.relativePath
                try? modelContext.save()
                Logger.transcripts.info("Transcript imported for \(item.originalFilename)")
            } catch {
                importError = error.localizedDescription
                Logger.transcripts.error("Transcript import failed: \(error.localizedDescription)")
            }
            isImporting = false
        }
    }

    private func removeTranscript() {
        guard let relativePath = item.transcriptRelativePath else { return }

        if let transcriptStore {
            Task {
                await transcriptStore.removeTranscript(
                    forContentHash: item.contentHash,
                    relativePath: relativePath
                )
            }
        }

        item.transcriptText = nil
        item.transcriptRelativePath = nil
        try? modelContext.save()
    }
}
