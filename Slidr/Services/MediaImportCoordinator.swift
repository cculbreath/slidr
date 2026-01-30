import Foundation
import SwiftData
import OSLog

/// Result of batch subtitle import.
struct SubtitleImportResult {
    var matched: [(item: MediaItem, file: URL)] = []
    var unmatched: [URL] = []

    var summary: String {
        if unmatched.isEmpty {
            return "Imported \(matched.count) subtitle(s)"
        }
        return "Imported \(matched.count), \(unmatched.count) unmatched"
    }
}

/// Coordinates media import operations, handling file imports, folder imports, and subtitle matching.
@MainActor
final class MediaImportCoordinator {
    private let modelContainer: ModelContainer
    private let transcriptStore: TranscriptStore
    var libraryRoot: URL
    var externalLibraryRoot: URL?

    private let fileManager = FileManager.default

    init(modelContainer: ModelContainer, transcriptStore: TranscriptStore, libraryRoot: URL) {
        self.modelContainer = modelContainer
        self.transcriptStore = transcriptStore
        self.libraryRoot = libraryRoot
    }

    // MARK: - File Import

    func importFiles(urls: [URL], options: ImportOptions, progressHandler: @escaping @Sendable (ImportProgress) -> Void) async throws -> ImportResult {
        let importer = MediaImporter(
            libraryRoot: libraryRoot,
            externalLibraryRoot: externalLibraryRoot,
            modelContext: modelContainer.mainContext,
            options: options
        )
        return try await importer.importFiles(urls: urls, progressHandler: progressHandler)
    }

    // MARK: - Folder Import

    func importFolders(urls: [URL], options: ImportOptions, progressHandler: @escaping @Sendable (ImportProgress) -> Void) async throws -> (result: ImportResult, folderGroups: [(name: String, items: [MediaItem])]) {
        // First pass: collect all files to get total count
        var allFolderFiles: [(name: String, fileURLs: [URL])] = []
        var looseFiles: [URL] = []
        var totalFileCount = 0

        for url in urls {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let mediaByFolder = collectMediaByFolder(in: url)
                for (folderName, fileURLs) in mediaByFolder {
                    allFolderFiles.append((name: folderName, fileURLs: fileURLs))
                    totalFileCount += fileURLs.count
                }
            } else {
                looseFiles.append(url)
            }
        }
        totalFileCount += looseFiles.count

        var combinedResult = ImportResult()
        var folderGroups: [(name: String, items: [MediaItem])] = []
        var processedCount = 0

        // Import folder files
        for (folderName, fileURLs) in allFolderFiles {
            let importer = MediaImporter(
                libraryRoot: libraryRoot,
                externalLibraryRoot: externalLibraryRoot,
                modelContext: modelContainer.mainContext,
                options: options
            )
            let baseCount = processedCount
            let folderResult = try await importer.importFiles(urls: fileURLs) { progress in
                progressHandler(ImportProgress(
                    currentItem: baseCount + progress.currentItem,
                    totalItems: totalFileCount,
                    currentFilename: progress.currentFilename,
                    phase: progress.phase
                ))
            }
            combinedResult.merge(folderResult)
            processedCount += fileURLs.count
            if !folderResult.imported.isEmpty {
                folderGroups.append((name: folderName, items: folderResult.imported))
            }
        }

        // Import loose files
        if !looseFiles.isEmpty {
            let importer = MediaImporter(
                libraryRoot: libraryRoot,
                externalLibraryRoot: externalLibraryRoot,
                modelContext: modelContainer.mainContext,
                options: options
            )
            let baseCount = processedCount
            let looseResult = try await importer.importFiles(urls: looseFiles) { progress in
                progressHandler(ImportProgress(
                    currentItem: baseCount + progress.currentItem,
                    totalItems: totalFileCount,
                    currentFilename: progress.currentFilename,
                    phase: progress.phase
                ))
            }
            combinedResult.merge(looseResult)
        }

        Logger.library.info("Folder import complete: \(combinedResult.summary)")
        return (result: combinedResult, folderGroups: folderGroups)
    }

    // MARK: - Subtitle Import

    func importSubtitles(urls: [URL], videoItems: [MediaItem]) async -> SubtitleImportResult {
        let subtitleExtensions: Set<String> = ["srt", "vtt"]
        let subtitleFiles = urls.filter { subtitleExtensions.contains($0.pathExtension.lowercased()) }

        guard !subtitleFiles.isEmpty else { return SubtitleImportResult() }

        // Build lookup tables
        let byUUID: [String: MediaItem] = Dictionary(
            uniqueKeysWithValues: videoItems.map { ($0.id.uuidString.lowercased(), $0) }
        )
        let byFilename: [String: MediaItem] = {
            var map: [String: MediaItem] = [:]
            for video in videoItems {
                let stem = (video.originalFilename as NSString).deletingPathExtension.lowercased()
                if map[stem] == nil {
                    map[stem] = video
                }
            }
            return map
        }()

        var result = SubtitleImportResult()

        for file in subtitleFiles {
            let stem = file.deletingPathExtension().lastPathComponent.lowercased()
            let matchedItem = byUUID[stem] ?? byFilename[stem]

            guard let item = matchedItem else {
                result.unmatched.append(file)
                Logger.transcripts.info("No match for subtitle: \(file.lastPathComponent)")
                continue
            }

            do {
                let importResult = try await transcriptStore.importTranscript(
                    from: file,
                    forContentHash: item.contentHash
                )
                item.transcriptText = importResult.plainText
                item.transcriptRelativePath = importResult.relativePath
                result.matched.append((item: item, file: file))
            } catch {
                result.unmatched.append(file)
                Logger.transcripts.error("Failed to import subtitle \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !result.matched.isEmpty {
            try? modelContainer.mainContext.save()
        }

        Logger.transcripts.info("Batch subtitle import: \(result.summary)")
        return result
    }

    // MARK: - Copy to Library

    func copyToLibrary(_ item: MediaItem) async throws {
        guard item.storageLocation == .referenced else { return }

        let sourceURL = URL(fileURLWithPath: item.relativePath)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw LibraryError.sourceFileNotFound
        }

        let year = Calendar.current.component(.year, from: Date())
        let yearDir = libraryRoot.appendingPathComponent("Local/\(year)", isDirectory: true)
        try fileManager.createDirectory(at: yearDir, withIntermediateDirectories: true)

        let destinationFilename = "\(UUID().uuidString).\(sourceURL.pathExtension)"
        let destinationURL = yearDir.appendingPathComponent(destinationFilename)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        item.relativePath = "Local/\(year)/\(destinationFilename)"
        item.storageLocation = .local
        try? modelContainer.mainContext.save()

        Logger.library.info("Copied to library: \(item.originalFilename)")
    }

    // MARK: - Private

    private func collectMediaByFolder(in url: URL) -> [(name: String, fileURLs: [URL])] {
        var folderMap: [String: [URL]] = [:]

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        while let fileURL = enumerator.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            guard FileTypeDetector.isSupported(fileURL) else { continue }

            let parentDir = fileURL.deletingLastPathComponent()
            folderMap[parentDir.path, default: []].append(fileURL)
        }

        return folderMap.sorted { $0.key < $1.key }
            .map { (name: URL(fileURLWithPath: $0.key).lastPathComponent, fileURLs: $0.value) }
    }
}
