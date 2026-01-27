import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

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
                    Text("Extra Large").tag(ThumbnailSize.extraLarge)
                }
            }
        }
        .formStyle(.grouped)
    }
}
