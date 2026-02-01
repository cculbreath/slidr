/// SlidrSchemaV13 — Current schema version
/// Adds: browserViewModeRaw on AppSettings
/// References live model definitions (MediaItem, Playlist, AppSettings).

import SwiftData

enum SlidrSchemaV13: VersionedSchema {
    static var versionIdentifier = Schema.Version(13, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MediaItem.self, Playlist.self, AppSettings.self]
    }
}
