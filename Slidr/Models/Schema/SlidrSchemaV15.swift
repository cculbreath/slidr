/// SlidrSchemaV15 — Current schema version
/// References live model definitions (MediaItem, Playlist, AppSettings).
///
/// V16 fields (imageText, audioCaptionRelativePath, playAudioCaptionsRaw)
/// are additive optional properties handled by automatic lightweight migration.

import SwiftData

enum SlidrSchemaV15: VersionedSchema {
    static var versionIdentifier = Schema.Version(15, 0, 0)

    static var models: [any PersistentModel.Type] {
        [MediaItem.self, Playlist.self, AppSettings.self]
    }
}
