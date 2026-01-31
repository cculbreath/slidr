import SwiftData
import Foundation
import OSLog

extension Logger {
    static let tagMigration = Logger(subsystem: "com.physicscloud.slidr", category: "TagMigration")
}

/// One-time tag cleanup: prune to allowlist, apply replacements, deduplicate.
enum TagCleanup {
    private static let completedKey = "tagCleanupV2Complete"

    static func runIfNeeded(container: ModelContainer, allowlistPath: String, replacementsPath: String) {
        guard !UserDefaults.standard.bool(forKey: completedKey) else {
            Logger.tagMigration.debug("Tag cleanup V2 already completed, skipping")
            return
        }

        let allowlist: Set<String>
        let replacements: [String: String]
        do {
            allowlist = try loadAllowlist(from: allowlistPath)
            replacements = try loadReplacements(from: replacementsPath)
        } catch {
            Logger.tagMigration.error("Failed to load tag cleanup files: \(error.localizedDescription)")
            return
        }

        Logger.tagMigration.info("Tag cleanup: \(allowlist.count) allowed tags, \(replacements.count) replacement rules")

        let context = ModelContext(container)
        do {
            let descriptor = FetchDescriptor<MediaItem>()
            let items = try context.fetch(descriptor)

            var totalModified = 0
            for item in items where !item.tags.isEmpty {
                let original = item.tags
                let cleaned = process(tags: original, allowlist: allowlist, replacements: replacements)
                if cleaned != original {
                    item.tags = cleaned
                    totalModified += 1
                }
            }

            if totalModified > 0 {
                try context.save()
                Logger.tagMigration.info("Tag cleanup complete: \(totalModified) items updated")
            } else {
                Logger.tagMigration.info("Tag cleanup: no items needed changes")
            }

            UserDefaults.standard.set(true, forKey: completedKey)
        } catch {
            Logger.tagMigration.error("Tag cleanup failed: \(error.localizedDescription)")
        }
    }

    /// Loads quoted tags, one per line: `"tagname"`
    private static func loadAllowlist(from path: String) throws -> Set<String> {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var set = Set<String>()
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let tag = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !tag.isEmpty else { continue }
            set.insert(tag.lowercased())
        }
        return set
    }

    /// Loads `"old", "new"` per line (with variable spacing around comma)
    private static func loadReplacements(from path: String) throws -> [String: String] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        var map: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.components(separatedBy: "\",")
            guard parts.count == 2 else { continue }

            let old = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let new = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            guard !old.isEmpty, !new.isEmpty else { continue }
            map[old.lowercased()] = new
        }
        return map
    }

    private static func process(tags: [String], allowlist: Set<String>, replacements: [String: String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for tag in tags {
            let key = tag.lowercased()

            // Step 1: drop tags not in the allowlist
            guard allowlist.contains(key) else { continue }

            // Step 2: apply replacement if one exists, always lowercase
            let final = (replacements[key] ?? tag).lowercased()

            // Step 3: deduplicate (case-insensitive)
            let dedupeKey = final.lowercased()
            if seen.insert(dedupeKey).inserted {
                result.append(final)
            }
        }

        return result
    }
}
