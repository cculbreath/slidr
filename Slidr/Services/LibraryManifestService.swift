import Foundation
import OSLog

/// Manages the app-level library manifest that tracks all known Slidr libraries.
///
/// The manifest lives at `~/Library/Application Support/Slidr/library-manifest.json`,
/// outside any library directory, so it's always accessible regardless of which
/// library is open.
@MainActor
@Observable
final class LibraryManifestService {
    private let manifestURL: URL
    private let slidrDirectory: URL
    private(set) var manifest: LibraryManifest

    init(slidrDirectory: URL) {
        self.slidrDirectory = slidrDirectory
        self.manifestURL = slidrDirectory.appendingPathComponent(LibraryManifest.filename)
        self.manifest = Self.load(from: self.manifestURL)
    }

    // MARK: - Persistence

    private static func load(from url: URL) -> LibraryManifest {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: data) else {
            return .empty
        }
        return manifest
    }

    func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    // MARK: - Library Management

    /// Creates a new library at `parentDirectory/name/`, sets up the internal
    /// directory structure, writes `library-info.json`, and registers it in the manifest.
    func createLibrary(name: String, at parentDirectory: URL) throws -> LibraryReference {
        let libraryDir = parentDirectory.appendingPathComponent(name, isDirectory: true)
        let fm = FileManager.default

        // Create directory structure
        try fm.createDirectory(
            at: libraryDir.appendingPathComponent("Library/Local", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: libraryDir.appendingPathComponent("Thumbnails", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: libraryDir.appendingPathComponent("Transcripts", isDirectory: true),
            withIntermediateDirectories: true
        )

        // Write library-info.json
        let info = LibraryInfo(id: UUID(), name: name, createdDate: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let infoData = try encoder.encode(info)
        try infoData.write(to: libraryDir.appendingPathComponent(LibraryInfo.filename))

        // Register in manifest
        let ref = LibraryReference(
            id: info.id,
            name: name,
            path: libraryDir.path,
            isDefault: false,
            lastOpenedDate: nil,
            itemCount: 0
        )
        manifest.libraries.append(ref)
        try save()

        Logger.library.info("Created new library '\(name)' at \(libraryDir.path)")
        return ref
    }

    /// Adds an existing library directory to the manifest. Reads `library-info.json`
    /// if present, otherwise generates a new identity from the directory name.
    func addExistingLibrary(at url: URL) throws -> LibraryReference {
        // Check for duplicate
        if let existing = manifest.libraries.first(where: { $0.path == url.path }) {
            return existing
        }

        let infoURL = url.appendingPathComponent(LibraryInfo.filename)
        let storeURL = url.appendingPathComponent("Slidr.store")

        // Verify this looks like a Slidr library
        let fm = FileManager.default
        guard fm.fileExists(atPath: infoURL.path) || fm.fileExists(atPath: storeURL.path) else {
            throw LibraryManifestError.notALibrary(url.path)
        }

        let ref: LibraryReference
        if let data = try? Data(contentsOf: infoURL),
           let info = try? JSONDecoder().decode(LibraryInfo.self, from: data) {
            ref = LibraryReference(
                id: info.id,
                name: info.name,
                path: url.path,
                isDefault: false,
                lastOpenedDate: nil,
                itemCount: nil
            )
        } else {
            // No library-info.json but has Slidr.store — generate identity from directory name
            ref = LibraryReference(
                id: UUID(),
                name: url.lastPathComponent,
                path: url.path,
                isDefault: false,
                lastOpenedDate: nil,
                itemCount: nil
            )
        }

        manifest.libraries.append(ref)
        try save()

        Logger.library.info("Added existing library '\(ref.name)' at \(url.path)")
        return ref
    }

    /// Removes a library reference from the manifest. Does NOT delete files.
    func removeReference(id: UUID) throws {
        manifest.libraries.removeAll { $0.id == id }
        if manifest.lastUsedLibraryID == id {
            manifest.lastUsedLibraryID = nil
        }
        try save()
    }

    /// Updates the last-opened timestamp and optional item count for a library.
    func markOpened(id: UUID, itemCount: Int?) throws {
        guard let index = manifest.libraries.firstIndex(where: { $0.id == id }) else { return }
        manifest.libraries[index].lastOpenedDate = Date()
        if let count = itemCount {
            manifest.libraries[index].itemCount = count
        }
        manifest.lastUsedLibraryID = id
        try save()
    }

    /// Updates the "always show picker" preference.
    func setAlwaysShowPicker(_ value: Bool) throws {
        manifest.alwaysShowPicker = value
        try save()
    }

    // MARK: - Queries

    /// The last-used library, if it exists in the manifest.
    var lastUsedLibrary: LibraryReference? {
        guard let id = manifest.lastUsedLibraryID else { return nil }
        return manifest.libraries.first { $0.id == id }
    }

    /// Libraries sorted by last opened date (most recent first), then by name.
    var sortedLibraries: [LibraryReference] {
        manifest.libraries.sorted { a, b in
            let aDate = a.lastOpenedDate ?? .distantPast
            let bDate = b.lastOpenedDate ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Migration

    /// On first run with multi-library support, if the legacy library exists
    /// at `~/Library/Application Support/Slidr/`, register it as "Default Library".
    func migrateDefaultLibraryIfNeeded() {
        guard manifest.libraries.isEmpty else { return }

        let storeURL = slidrDirectory.appendingPathComponent("Slidr.store")
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let ref = LibraryReference(
            id: UUID(),
            name: "Default Library",
            path: slidrDirectory.path,
            isDefault: true,
            lastOpenedDate: Date(),
            itemCount: nil
        )
        manifest.libraries.append(ref)
        manifest.lastUsedLibraryID = ref.id
        try? save()

        Logger.library.info("Migrated legacy library as 'Default Library'")
    }
}

// MARK: - Errors

enum LibraryManifestError: LocalizedError {
    case notALibrary(String)

    var errorDescription: String? {
        switch self {
        case .notALibrary(let path):
            return "The selected directory does not appear to be a Slidr library: \(path)"
        }
    }
}
