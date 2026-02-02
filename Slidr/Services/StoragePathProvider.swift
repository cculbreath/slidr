import Foundation

/// Centralized path resolution for vault vs non-vault mode.
///
/// When vault mode is active, all paths resolve into the mounted vault volume.
/// When vault mode is inactive, paths resolve to the standard Application Support directory.
@MainActor
final class StoragePathProvider {
    let slidrDirectory: URL
    let vaultMode: Bool

    /// Mount point of the local vault (database, thumbnails, transcripts, local media).
    private let localVaultMount: URL?

    /// Mount points of external vaults keyed by vault ID.
    private let externalVaultMounts: [UUID: URL]

    init(
        slidrDirectory: URL,
        vaultMode: Bool = false,
        localVaultMount: URL? = nil,
        externalVaultMounts: [UUID: URL] = [:]
    ) {
        self.slidrDirectory = slidrDirectory
        self.vaultMode = vaultMode
        self.localVaultMount = localVaultMount
        self.externalVaultMounts = externalVaultMounts
    }

    /// Convenience initializer for non-vault mode.
    convenience init(slidrDirectory: URL) {
        self.init(slidrDirectory: slidrDirectory, vaultMode: false)
    }

    // MARK: - Resolved Paths

    var databaseURL: URL {
        baseDirectory.appendingPathComponent("Slidr.store")
    }

    var thumbnailCacheURL: URL {
        baseDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    var transcriptStoreURL: URL {
        baseDirectory.appendingPathComponent("Transcripts", isDirectory: true)
    }

    var libraryRootURL: URL {
        baseDirectory.appendingPathComponent("Library", isDirectory: true)
    }

    // MARK: - External Vaults

    func externalVaultMount(for vaultID: UUID) -> URL? {
        externalVaultMounts[vaultID]
    }

    var allExternalMounts: [UUID: URL] {
        externalVaultMounts
    }

    // MARK: - Private

    private var baseDirectory: URL {
        if vaultMode, let mount = localVaultMount {
            return mount
        }
        return slidrDirectory
    }
}
