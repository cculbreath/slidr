import SwiftUI
import SwiftData
import OSLog

struct SettingsView: View {
    @Query private var settingsQuery: [AppSettings]

    let thumbnailCache: ThumbnailCache

    private var settings: AppSettings {
        guard let existing = settingsQuery.first else {
            // AppSettings is bootstrapped in SlidrApp.init — this should never happen
            Logger.library.error("AppSettings missing from database — this indicates a startup failure")
            fatalError("AppSettings not found. The database may be corrupted.")
        }
        return existing
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
