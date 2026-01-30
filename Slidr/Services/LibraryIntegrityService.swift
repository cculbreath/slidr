import Foundation
import SwiftData
import OSLog

/// Service responsible for library integrity verification and orphan cleanup.
@MainActor
final class LibraryIntegrityService {
    private let modelContainer: ModelContainer
    private let thumbnailCache: ThumbnailCache
    private let queryService: MediaQueryService
    private let fileManager = FileManager.default

    init(modelContainer: ModelContainer, thumbnailCache: ThumbnailCache, queryService: MediaQueryService) {
        self.modelContainer = modelContainer
        self.thumbnailCache = thumbnailCache
        self.queryService = queryService
    }

    // MARK: - Verification

    func verifyIntegrity(urlResolver: (MediaItem) -> URL, isExternalDriveConnected: Bool) async -> VerificationResult {
        let startTime = Date()
        let items = queryService.allItems
        let totalItems = items.count
        var verifiedCount = 0
        var missingCount = 0

        for item in items {
            let url = urlResolver(item)
            if fileManager.fileExists(atPath: url.path) {
                if item.status == .missing {
                    item.status = .available
                }
                item.lastVerifiedDate = Date()
                verifiedCount += 1
            } else if item.storageLocation == .external && !isExternalDriveConnected {
                item.status = .externalNotMounted
                item.lastVerifiedDate = Date()
            } else {
                item.status = .missing
                item.lastVerifiedDate = Date()
                missingCount += 1
            }
        }

        try? modelContainer.mainContext.save()

        let orphanedCount = await countOrphanedThumbnails()

        let duration = Date().timeIntervalSince(startTime)
        Logger.library.info("Library verification complete: \(verifiedCount)/\(totalItems) verified, \(missingCount) missing, \(orphanedCount) orphaned thumbnails")

        return VerificationResult(
            totalItems: totalItems,
            verifiedItems: verifiedCount,
            missingItems: missingCount,
            orphanedThumbnails: orphanedCount,
            duration: duration
        )
    }

    // MARK: - Orphan Cleanup

    func cleanOrphanedThumbnails() async {
        let existingHashes = Set(queryService.allItems.map(\.contentHash))
        await thumbnailCache.pruneOrphanedThumbnails(existingHashes: existingHashes)
        Logger.library.info("Orphaned thumbnail cleanup complete")
    }

    func removeOrphanedItems() {
        let orphaned = queryService.allItems.filter { $0.status == .missing }
        guard !orphaned.isEmpty else { return }

        for item in orphaned {
            Task {
                await thumbnailCache.removeThumbnails(forHash: item.contentHash)
            }
            modelContainer.mainContext.delete(item)
        }

        try? modelContainer.mainContext.save()
        Logger.library.info("Removed \(orphaned.count) orphaned items with .missing status")
    }

    func countOrphanedThumbnails() async -> Int {
        let existingHashes = Set(queryService.allItems.map(\.contentHash))
        let diskCount = await thumbnailCache.diskCacheCount()
        let expectedMaxThumbnails = existingHashes.count * ThumbnailSize.allCases.count
        return max(0, diskCount - expectedMaxThumbnails)
    }
}
