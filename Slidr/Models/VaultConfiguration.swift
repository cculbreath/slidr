import Foundation

/// Configuration for a single encrypted vault (one per drive/location).
struct VaultConfiguration: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let bundlePath: String
    let mountPointName: String
    let driveType: DriveType
    let volumeUUID: String?
    let createdDate: Date
    var isEnabled: Bool

    enum DriveType: String, Codable, Sendable {
        case local
        case external
    }

    var mountPoint: URL {
        URL(fileURLWithPath: "/Volumes/\(mountPointName)")
    }
}

/// Registry of all vault locations, stored as JSON outside the vault.
struct VaultManifest: Codable, Sendable {
    var vaults: [VaultConfiguration]
    var useKeychain: Bool
    var autoLockOnSleep: Bool
    var autoLockOnScreensaver: Bool
    var lockTimeoutMinutes: Int?

    nonisolated static let filename = "vault-manifest.json"

    nonisolated static var empty: VaultManifest {
        VaultManifest(
            vaults: [],
            useKeychain: false,
            autoLockOnSleep: true,
            autoLockOnScreensaver: true,
            lockTimeoutMinutes: nil
        )
    }
}
