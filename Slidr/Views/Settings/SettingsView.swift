import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsQuery: [AppSettings]

    let thumbnailCache: ThumbnailCache

    private var settings: AppSettings {
        if let existing = settingsQuery.first {
            return existing
        }
        let newSettings = AppSettings()
        modelContext.insert(newSettings)
        return newSettings
    }

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ImportSettingsView(settings: settings)
                .tabItem {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

            SlideshowSettingsView(settings: settings)
                .tabItem {
                    Label("Slideshow", systemImage: "play.rectangle")
                }

            CacheSettingsView(settings: settings, thumbnailCache: thumbnailCache)
                .tabItem {
                    Label("Cache", systemImage: "internaldrive")
                }
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}
