import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

struct TranscriptSection: View {
    @Bindable var item: MediaItem
    @Environment(\.transcriptStore) private var transcriptStore
    @Environment(\.transcriptSeekAction) private var seekAction
    @Environment(\.modelContext) private var modelContext

    @State private var isImporting = false
    @State private var importError: String?
    @State private var transcriptCues: [TranscriptCue] = []
    @State private var isExpanded = false

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
        .onAppear { loadCues() }
        .onChange(of: item.id) { loadCues() }
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

            // Expandable transcript cues
            DisclosureGroup("Transcript", isExpanded: $isExpanded) {
                if transcriptCues.isEmpty {
                    Text("No cues loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(transcriptCues, id: \.index) { cue in
                                cueRow(cue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .font(.caption)

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

    @ViewBuilder
    private func cueRow(_ cue: TranscriptCue) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let seekAction {
                Button {
                    seekAction(cue.startTime)
                } label: {
                    Text("[\(formatTimestamp(cue.startTime))]")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else {
                Text("[\(formatTimestamp(cue.startTime))]")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(stripHTMLTags(cue.text))
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func stripHTMLTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private var importButton: some View {
        Button {
            importTranscript()
        } label: {
            if isImporting {
                SpinnerView()
            } else {
                Label("Import SRT/VTT...", systemImage: "captions.bubble")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isImporting)
    }

    private func loadCues() {
        transcriptCues = []
        guard let transcriptStore,
              item.hasTranscript,
              let relativePath = item.transcriptRelativePath else { return }

        let contentHash = item.contentHash
        Task {
            do {
                let cues = try await transcriptStore.cues(
                    forContentHash: contentHash,
                    relativePath: relativePath
                )
                transcriptCues = cues
            } catch {
                Logger.transcripts.error("Failed to load transcript cues: \(error.localizedDescription)")
            }
        }
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
                loadCues()
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
        transcriptCues = []
        isExpanded = false
        try? modelContext.save()
    }
}
