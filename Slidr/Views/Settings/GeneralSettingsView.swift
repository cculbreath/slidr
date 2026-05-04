import SwiftUI
import SwiftData

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @State private var aiImporter = AIMetadataImporter()
    @State private var importResult: AIMetadataImportResult?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Show welcome screen on launch", isOn: $settings.showWelcomeOnLaunch)
            }

            Section("Behavior") {
                Toggle("Confirm before deleting items", isOn: $settings.confirmBeforeDelete)

                Picker("Default sort order", selection: $settings.defaultSortOrder) {
                    Text("Name").tag(SortOrder.name)
                    Text("Date Modified").tag(SortOrder.dateModified)
                    Text("Date Imported").tag(SortOrder.dateImported)
                    Text("File Size").tag(SortOrder.fileSize)
                }

                Toggle("Sort ascending by default", isOn: $settings.defaultSortAscending)
            }

            Section("Display") {
                Picker("Default thumbnail size", selection: $settings.defaultThumbnailSize) {
                    Text("Small").tag(ThumbnailSize.small)
                    Text("Medium").tag(ThumbnailSize.medium)
                    Text("Large").tag(ThumbnailSize.large)

                }

                Toggle("Animate GIFs in grid", isOn: $settings.animateGIFsInGrid)

                Text("Enabling GIF animation may increase memory usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Metadata") {
                Button("Import Tags & Summaries...") {
                    pickDirectoryAndImport()
                }
                .disabled(aiImporter.isImporting)

                if aiImporter.isImporting {
                    ProgressView("Processing \(aiImporter.processedCount) of \(aiImporter.totalCount)...",
                                 value: Double(aiImporter.processedCount),
                                 total: Double(max(aiImporter.totalCount, 1)))
                }

                if let result = importResult {
                    Text("Updated \(result.updated) items. \(result.notFound) files had no match.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pickDirectoryAndImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select directory containing AI metadata JSON files"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        importResult = nil
        Task {
            do {
                let result = try await aiImporter.importMetadata(from: url, modelContext: modelContext)
                importResult = result
            } catch {
                importResult = AIMetadataImportResult(notFound: 0, totalFiles: 0)
            }
        }
    }

}
