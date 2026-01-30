import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var showLibraryLocationPicker = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Library Location") {
                HStack {
                    if let customPath = settings.customLibraryPath {
                        Text(shortenedPath(customPath))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Default Location")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Change...") {
                        showLibraryLocationPicker = true
                    }

                    if settings.customLibraryPath != nil {
                        Button("Reset") {
                            showResetConfirmation = true
                        }
                    }
                }

                Text(settings.resolvedLibraryPath.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

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
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showLibraryLocationPicker) {
            LibraryLocationPicker(
                currentPath: settings.customLibraryPath,
                onSelect: { newPath in
                    settings.customLibraryPath = newPath
                }
            )
        }
        .confirmationDialog(
            "Reset Library Location",
            isPresented: $showResetConfirmation
        ) {
            Button("Reset to Default", role: .destructive) {
                settings.customLibraryPath = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will change the library location back to the default. Existing files will not be moved.")
        }
    }

    private func shortenedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
