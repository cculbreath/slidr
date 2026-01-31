import Foundation
import SwiftData
import OSLog

struct AIMetadataImportResult {
    var updated: Int = 0
    var skipped: Int = 0
    var notFound: Int = 0
    var totalFiles: Int = 0
}

@MainActor
@Observable
final class AIMetadataImporter {
    var isImporting = false
    var processedCount = 0
    var totalCount = 0

    func importMetadata(from directoryURL: URL, modelContext: ModelContext) async throws -> AIMetadataImportResult {
        isImporting = true
        processedCount = 0
        defer { isImporting = false }

        // Enumerate JSON files
        let fileManager = FileManager.default
        let jsonFiles = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }

        totalCount = jsonFiles.count

        // Build lookup: filename stem (from relativePath) -> MediaItem
        let fetchDescriptor = FetchDescriptor<MediaItem>()
        let allItems = try modelContext.fetch(fetchDescriptor)
        var lookup: [String: MediaItem] = [:]
        for item in allItems {
            let stem = (item.relativePath as NSString).lastPathComponent
                .replacingOccurrences(of: ".\((item.relativePath as NSString).pathExtension)", with: "")
            lookup[stem] = item
        }

        var result = AIMetadataImportResult()
        result.totalFiles = jsonFiles.count

        for jsonURL in jsonFiles {
            let uuid = jsonURL.deletingPathExtension().lastPathComponent

            guard let item = lookup[uuid] else {
                result.notFound += 1
                processedCount += 1
                continue
            }

            do {
                let data = try Data(contentsOf: jsonURL)
                let metadata = try JSONDecoder().decode(AIMetadataJSON.self, from: data)

                // Merge tags (replace underscores with spaces)
                let allTags = (metadata.tags ?? []) + (metadata.priority_tags ?? [])
                for tag in allTags {
                    let cleaned = tag.replacingOccurrences(of: "_", with: " ")
                    item.addTag(cleaned)
                }

                // Set summary (strip wrapping quotes)
                if let summary = metadata.summary {
                    var cleaned = summary
                    if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count >= 2 {
                        cleaned = String(cleaned.dropFirst().dropLast())
                    }
                    item.summary = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Set production only if currently nil
                if item.production == nil, let source = metadata.production_source {
                    item.production = mapProduction(source)
                }

                result.updated += 1
            } catch {
                Logger.library.warning("Failed to decode AI metadata from \(jsonURL.lastPathComponent): \(error.localizedDescription)")
                result.skipped += 1
            }

            processedCount += 1

            // Save in batches of 100
            if processedCount % 100 == 0 {
                try modelContext.save()
            }
        }

        try modelContext.save()
        return result
    }

    private func mapProduction(_ source: String) -> ProductionType? {
        switch source.lowercased() {
        case "amateur", "homemade":
            return .homemade
        case "professional", "studio":
            return .professional
        case "semi-professional", "creator":
            return .creator
        default:
            return nil
        }
    }
}

private struct AIMetadataJSON: Decodable {
    let tags: [String]?
    let summary: String?
    let priority_tags: [String]?
    let production_source: String?
    let production_confidence: Double?
}
