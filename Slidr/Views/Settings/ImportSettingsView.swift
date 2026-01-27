import SwiftUI

struct ImportSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("File Handling") {
                Toggle("Copy new files to library", isOn: $settings.copyFilesToLibrary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("When enabled, imported files are copied to the library folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("When disabled, files remain in their original location and are referenced by the library. Referenced files become unavailable if moved or deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("This setting only affects new imports. Existing files are not changed.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.top, 2)

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
            }

            Section("Storage") {
                Picker("Default import location", selection: $settings.defaultImportLocation) {
                    Text("Local Library").tag(StorageLocation.local)
                    Text("External Drive").tag(StorageLocation.external)
                }
            }

            Section("External Storage") {
                HStack {
                    if let path = settings.externalDrivePath {
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

                Text("Secondary library location on external drive.")
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
