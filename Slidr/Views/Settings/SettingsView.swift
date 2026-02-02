import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var settingsQuery: [AppSettings]

    let thumbnailCache: ThumbnailCache

    private var settings: AppSettings? {
        settingsQuery.first
    }

    var body: some View {
        if let settings {
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

                AISettingsView(settings: settings)
                    .tabItem {
                        Label("Intelligence", systemImage: "sparkles")
                    }
            }
            .frame(width: 500, height: 400)
            .padding()
        } else {
            ContentUnavailableView(
                "Settings Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("Unable to load application settings. Try restarting the app.")
            )
            .frame(width: 500, height: 400)
            .padding()
        }
    }
}
