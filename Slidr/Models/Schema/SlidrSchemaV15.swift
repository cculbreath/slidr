/// SlidrSchemaV15 — Current schema version
/// Adds: filterSources ([String]?) on Playlist for source-based filtering
/// References live model definitions (MediaItem, Playlist, AppSettings).

import SwiftData

enum SlidrSchemaV15: VersionedSchema {
    static var versionIdentifier = Schema.Version(15, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MediaItem.self, Playlist.self, AppSettings.self]
    }
}
