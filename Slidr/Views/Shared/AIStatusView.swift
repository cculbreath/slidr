import SwiftUI

struct AIStatusView: View {
    @Environment(AIProcessingCoordinator.self) private var coordinator
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            if coordinator.isProcessing {
                progressSection
            } else if !coordinator.operationLog.isEmpty {
                completionSection
            }
            if !coordinator.operationLog.isEmpty {
                logSection
            }
            footerSection
        }
        .padding(16)
        .frame(minWidth: 340, maxWidth: 440)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            if coordinator.isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text(statusTitle)
                    .font(.headline)
            } else if hasErrors {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Completed with Errors")
                    .font(.headline)
            } else if !coordinator.operationLog.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Complete")
                    .font(.headline)
            } else {
                Text("AI Processing")
                    .font(.headline)
            }
            Spacer()
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if coordinator.totalCount > 0 {
                ProgressView(value: Double(coordinator.processedCount), total: Double(coordinator.totalCount))
                HStack {
                    if let item = coordinator.currentItem {
                        Text(item.originalFilename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text("\(coordinator.processedCount)/\(coordinator.totalCount)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Completion

    private var completionSection: some View {
        let successCount = coordinator.operationLog.filter { if case .success = $0.status { return true }; return false }.count
        let failureCount = coordinator.operationLog.filter { if case .failure = $0.status { return true }; return false }.count

        return HStack(spacing: 16) {
            if successCount > 0 {
                Label("\(successCount) succeeded", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            if failureCount > 0 {
                Label("\(failureCount) failed", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }

    // MARK: - Log

    private var logSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(coordinator.operationLog.reversed()) { entry in
                    logRow(entry)
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func logRow(_ entry: AIOperationLog) -> some View {
        HStack(alignment: .top, spacing: 6) {
            switch entry.status {
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.operation): \(entry.itemName)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if case .failure(let message) = entry.status {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if coordinator.isProcessing {
                Button("Cancel") {
                    coordinator.cancel()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            if !coordinator.isProcessing && !coordinator.operationLog.isEmpty {
                Button("Clear Log") {
                    coordinator.clearLog()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Helpers

    private var statusTitle: String {
        guard !coordinator.currentOperation.isEmpty else { return "Processing..." }
        return "\(coordinator.currentOperation)..."
    }

    private var hasErrors: Bool {
        coordinator.operationLog.contains { if case .failure = $0.status { return true }; return false }
    }
}
