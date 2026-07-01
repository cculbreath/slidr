import SwiftUI

/// Bottom-of-sidebar pane that surfaces background work which would otherwise be
/// invisible: AI tag/transcribe/summarize batches, scrub-thumbnail generation,
/// missing-API-key notices, and any per-item failures those produce.
///
/// Renders nothing when idle and clean, so it only claims sidebar height when
/// there is something to report. Failures persist until dismissed (or superseded
/// by the next run), which is the whole point — AI ops used to fail silently.
struct SidebarActivityPane: View {
    @Environment(AIProcessingCoordinator.self) private var ai
    @Environment(MediaLibrary.self) private var library

    @State private var errorsExpanded = false

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                if ai.isProcessing {
                    aiProgressRow
                }
                if let progress = library.scrubThumbnailProgress {
                    thumbnailRow(progress)
                }
                if let notice = ai.configError {
                    configNoticeRow(notice)
                }
                if !failures.isEmpty {
                    errorSection
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    // MARK: - AI Progress

    private var aiProgressRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SpinnerView()
                Text(ai.currentOperation.isEmpty ? "Processing" : ai.currentOperation)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    ai.cancel()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Cancel processing")
            }
            if ai.totalCount > 0 {
                ProgressView(value: Double(ai.processedCount), total: Double(ai.totalCount))
                    .controlSize(.small)
                HStack {
                    if let name = ai.currentItem?.originalFilename {
                        Text(name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text("\(ai.processedCount)/\(ai.totalCount)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Thumbnail Generation

    private func thumbnailRow(_ progress: ScrubThumbnailProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "film.stack")
                    .foregroundStyle(.secondary)
                Text("Generating thumbnails")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
            }
            ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                .controlSize(.small)
            HStack {
                Spacer()
                Text("\(progress.completed)/\(progress.total)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Config Notice

    private func configNoticeRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                ai.dismissConfigError()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
        .padding(6)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Errors

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                errorsExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("\(failures.count) failed")
                        .fontWeight(.medium)
                    if ai.processedCount > 0 {
                        Text("· \(ai.processedCount) processed")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: errorsExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if errorsExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(failures) { entry in
                            failureRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 160)

                HStack {
                    Spacer()
                    Button("Clear") {
                        ai.clearLog()
                        errorsExpanded = false
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
        .padding(6)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func failureRow(_ entry: AIOperationLog) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption2)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.operation): \(entry.itemName)")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .failure(let message) = entry.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Derived State

    /// Newest-first failures from the current run's log.
    private var failures: [AIOperationLog] {
        Array(ai.operationLog.filter { if case .failure = $0.status { return true }; return false }.reversed())
    }

    private var hasContent: Bool {
        ai.isProcessing
            || library.scrubThumbnailProgress != nil
            || ai.configError != nil
            || !failures.isEmpty
    }
}
