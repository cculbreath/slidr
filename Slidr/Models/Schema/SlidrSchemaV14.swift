/// SlidrSchemaV14 — Current schema version
/// Adds: AI processing properties to AppSettings (aiAutoProcessOnImportRaw,
///   aiAutoTranscribeOnImportRaw, aiModelRaw, aiTagModeRaw, groqModelRaw)
/// References live model definitions (MediaItem, Playlist, AppSettings).

import SwiftData

enum SlidrSchemaV14: VersionedSchema {
    static var versionIdentifier = Schema.Version(14, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MediaItem.self, Playlist.self, AppSettings.self]
    }
}
