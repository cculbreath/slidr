import SwiftUI

struct ImportSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Import Behavior") {
                Picker("When importing files", selection: $settings.importMode) {
                    Text("Copy to Library").tag(ImportMode.copy)
                    Text("Move to Library").tag(ImportMode.move)
                    Text("Reference in Place").tag(ImportMode.reference)
                }

                Text(settings.importMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.importMode == .reference {
                    Text("This setting only affects new imports. Existing files are not changed.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("Skip duplicate files", isOn: $settings.skipDuplicates)
            }

            Section("Video Conversion") {
                Toggle("Convert incompatible formats", isOn: $settings.convertIncompatibleFormats)

                if settings.convertIncompatibleFormats {
                    Toggle("Keep original file after conversion", isOn: $settings.keepOriginalAfterConversion)

                    Picker("Target format", selection: $settings.importTargetFormat) {
                        ForEach(VideoFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }

                    Text(settings.importTargetFormat.formatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Organization") {
                Toggle("Organize imports by date", isOn: $settings.importOrganizeByDate)

                if settings.importOrganizeByDate {
                    Text("Files will be organized into Year/Month folders based on file modification date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Create playlists from folders", isOn: $settings.createPlaylistsFromFolders)

                if settings.createPlaylistsFromFolders {
                    Text("When importing folders, a playlist will be created for each folder that contains media files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Storage Target") {
                Picker("Default import location", selection: $settings.defaultImportLocation) {
                    Text("Local Library").tag(StorageLocation.local)
                    Text("External Drive").tag(StorageLocation.external)
                }

                if settings.defaultImportLocation == .external && settings.externalDrivePath == nil {
                    Text("Configure an external storage path below to import to an external drive.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("External Storage") {
                HStack {
                    if let path = settings.externalDrivePath {
                        let isConnected = FileManager.default.fileExists(atPath: path)
                        Image(systemName: isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isConnected ? .green : .red)
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Not configured")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Browse...") {
                        selectExternalPath()
                    }

                    if settings.externalDrivePath != nil {
                        Button("Clear") {
                            settings.externalDrivePath = nil
                        }
                    }
                }

                Text("Location for the external media library. Files imported with 'External Drive' storage will be stored here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func selectExternalPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose external library location"

        if panel.runModal() == .OK, let url = panel.url {
            settings.externalDrivePath = url.path
        }
    }
}
