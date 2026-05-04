import Foundation

/// A reference to a known Slidr library, stored in the app-level manifest.
struct LibraryReference: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var path: String
    var isDefault: Bool
    var lastOpenedDate: Date?
    var itemCount: Int?

    var url: URL { URL(fileURLWithPath: path) }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// App-level registry of all known libraries, stored as JSON outside any library.
/// Location: ~/Library/Application Support/Slidr/library-manifest.json
struct LibraryManifest: Codable, Sendable {
    var libraries: [LibraryReference]
    var lastUsedLibraryID: UUID?
    var alwaysShowPicker: Bool

    nonisolated static let filename = "library-manifest.json"

    nonisolated static var empty: LibraryManifest {
        LibraryManifest(libraries: [], lastUsedLibraryID: nil, alwaysShowPicker: false)
    }
}

/// Metadata written inside each library directory as `library-info.json`.
/// Used to identify a directory as a Slidr library and to recover library identity
/// when adding an existing library via the picker.
struct LibraryInfo: Codable, Sendable {
    let id: UUID
    let name: String
    let createdDate: Date

    static let filename = "library-info.json"
}
