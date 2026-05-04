import Foundation
import SwiftData
import OSLog

/// Result of a manifest-based import operation.
struct ManifestImportResult {
    var totalFiles: Int = 0
    var imported: Int = 0
    var captionsApplied: Int = 0
    var duplicatesSkipped: Int = 0
    var playlistsCreated: [String] = []

    var summary: String {
        var parts = ["\(imported) imported"]
        if captionsApplied > 0 { parts.append("\(captionsApplied) captions") }
        if duplicatesSkipped > 0 { parts.append("\(duplicatesSkipped) duplicates skipped") }
        if !playlistsCreated.isEmpty { parts.append("\(playlistsCreated.count) playlists") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Manifest JSON Model

/// Represents the manifest.json format from a download export.
/// Structure: { username, downloadDate, boards: { boardName: { pins: [...] } } }
struct DownloadManifest: Codable {
    let username: String?
    let downloadDate: String?
    let boards: [String: Board]

    struct Board: Codable {
        let pins: [Pin]
    }

    struct Pin: Codable {
        let filename: String
        let caption: String?
        let pinId: String?
        let originalUrl: String?
    }
}

/// Imports media from a directory that contains board subdirectories and an optional
/// manifest.json with captions. Creates a playlist per board and applies captions
/// from the manifest to matching imported items.
@MainActor
@Observable
final class ManifestImporter {
    private(set) var isImporting = false
    private(set) var progressMessage = ""
    private(set) var progress: Double?
    private(set) var currentBoard = ""

    /// Import media from a directory containing board subdirectories and a manifest.json.
    func importFromManifest(
        rootURL: URL,
        mediaLibrary: MediaLibrary,
        playlistService: PlaylistService,
        options: ImportOptions = ImportOptions()
    ) async throws -> ManifestImportResult {
        isImporting = true
        defer { isImporting = false; progressMessage = ""; progress = nil; currentBoard = "" }

        var result = ManifestImportResult()

        // 1. Parse manifest.json if it exists
        progressMessage = "Reading manifest..."
        progress = 0
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let captionsByPinId = Self.buildCaptionLookup(from: manifestURL)

        // 2. Discover board directories
        let fm = FileManager.default
        let boardDirs = try fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { url in
                let vals = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return vals?.isDirectory == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !boardDirs.isEmpty else {
            Logger.importing.warning("No board directories found in \(rootURL.path)")
            return result
        }

        // 3. Import each board individually for progress tracking
        let totalBoards = boardDirs.count
        var allFolderGroups: [(name: String, items: [MediaItem])] = []

        for (index, boardDir) in boardDirs.enumerated() {
            let boardName = boardDir.lastPathComponent
            currentBoard = boardName
            progressMessage = "Importing board \(index + 1) of \(totalBoards): \(boardName)"
            progress = Double(index) / Double(totalBoards + 1)

            let (importResult, _) = try await mediaLibrary.importFolders(
                urls: [boardDir],
                options: options
            )

            result.totalFiles += importResult.imported.count + importResult.skippedDuplicates.count
            result.imported += importResult.imported.count
            result.duplicatesSkipped += importResult.skippedDuplicates.count

            if !importResult.imported.isEmpty {
                allFolderGroups.append((name: boardName, items: importResult.imported))
            }
        }

        // 4. Apply captions
        if !captionsByPinId.isEmpty {
            progressMessage = "Applying captions..."
            progress = Double(totalBoards) / Double(totalBoards + 1)
            result.captionsApplied = try Self.applyCaptionsToItems(
                captionsByPinId: captionsByPinId,
                context: mediaLibrary.modelContainer.mainContext
            )
        }

        // 5. Create playlists per board
        progressMessage = "Creating playlists..."
        progress = 1.0
        for (boardName, items) in allFolderGroups {
            let playlist = playlistService.createPlaylist(name: boardName, type: .manual)
            playlistService.addItems(items, to: playlist)
            result.playlistsCreated.append(boardName)
        }

        Logger.importing.info("Manifest import complete: \(result.summary)")
        return result
    }

    /// Apply captions from a manifest.json file to existing items in the library.
    /// No file importing — just reads the manifest and matches captions by pinId.
    func applyCaptions(
        manifestURL: URL,
        mediaLibrary: MediaLibrary
    ) async throws -> ManifestImportResult {
        isImporting = true
        defer { isImporting = false; progressMessage = ""; progress = nil; currentBoard = "" }

        var result = ManifestImportResult()

        progressMessage = "Reading manifest..."
        progress = 0

        let captionsByPinId = Self.buildCaptionLookup(from: manifestURL)

        guard !captionsByPinId.isEmpty else {
            Logger.importing.warning("No usable captions found in manifest at \(manifestURL.path)")
            return result
        }

        progressMessage = "Applying captions..."
        progress = 0.5

        result.captionsApplied = try Self.applyCaptionsToItems(
            captionsByPinId: captionsByPinId,
            context: mediaLibrary.modelContainer.mainContext
        )

        result.totalFiles = captionsByPinId.count
        Logger.importing.info("Caption apply complete: \(result.summary)")
        return result
    }

    // MARK: - Private

    private static func loadManifest(from url: URL) -> DownloadManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DownloadManifest.self, from: data)
    }

    /// Builds a pinId → caption lookup from a manifest file.
    /// Pin IDs are the numeric prefix of each filename (e.g., "54526658" from "54526658-Girlfriend.gif").
    private static func buildCaptionLookup(from manifestURL: URL) -> [String: String] {
        guard let manifest = loadManifest(from: manifestURL) else { return [:] }

        var captionsByPinId: [String: String] = [:]
        for (_, board) in manifest.boards {
            for pin in board.pins {
                guard let caption = pin.caption, caption != "untitled", !caption.isEmpty else { continue }

                // Use explicit pinId if available, otherwise extract from filename
                let pinId = pin.pinId ?? Self.extractPinId(from: pin.filename)
                guard let pinId else { continue }
                captionsByPinId[pinId] = caption
            }
        }

        Logger.importing.info("Manifest loaded: \(captionsByPinId.count) captions across \(manifest.boards.count) boards")
        return captionsByPinId
    }

    /// Extracts the numeric pinId prefix from a filename.
    /// e.g., "54526658-Girlfriend.gif" → "54526658"
    /// e.g., "54526658 Girlfriend.gif" → "54526658"
    private static func extractPinId(from filename: String) -> String? {
        // Take leading digits before any separator (dash, space, underscore)
        let digits = filename.prefix(while: { $0.isNumber })
        return digits.isEmpty ? nil : String(digits)
    }

    /// Matches items in the database to captions by pinId and saves.
    /// Returns the number of captions applied.
    private static func applyCaptionsToItems(
        captionsByPinId: [String: String],
        context: ModelContext
    ) throws -> Int {
        let descriptor = FetchDescriptor<MediaItem>()
        let allItems: [MediaItem]
        do {
            allItems = try context.fetch(descriptor)
        } catch {
            Logger.importing.error("Failed to fetch items for caption matching: \(error)")
            throw error
        }

        Logger.importing.info("Caption matching: \(captionsByPinId.count) captions to match against \(allItems.count) items")

        var applied = 0
        for item in allItems {
            guard let pinId = extractPinId(from: item.originalFilename) else { continue }
            guard let caption = captionsByPinId[pinId] else { continue }
            item.caption = caption
            applied += 1
        }

        if applied > 0 {
            do {
                try context.save()
                Logger.importing.info("Saved \(applied) captions")
            } catch {
                Logger.importing.error("Failed to save captions: \(error)")
                throw error
            }
        } else {
            Logger.importing.warning("No captions matched. Sample DB filenames: \(allItems.prefix(3).map(\.originalFilename)). Sample pinIds in manifest: \(Array(captionsByPinId.keys.prefix(3)))")
        }

        return applied
    }
}
