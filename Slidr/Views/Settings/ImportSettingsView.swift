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

                    Text("Incompatible formats (AVI, WMV, etc.) will be converted to MP4 for better playback.")
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
        }
        .formStyle(.grouped)
    }
}
