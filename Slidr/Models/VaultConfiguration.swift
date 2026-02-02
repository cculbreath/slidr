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
struct VaultManifest: Sendable {
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

extension VaultManifest: Codable {
    private enum CodingKeys: String, CodingKey {
        case vaults, useKeychain, autoLockOnSleep, autoLockOnScreensaver, lockTimeoutMinutes
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vaults = try container.decode([VaultConfiguration].self, forKey: .vaults)
        useKeychain = try container.decode(Bool.self, forKey: .useKeychain)
        autoLockOnSleep = try container.decode(Bool.self, forKey: .autoLockOnSleep)
        autoLockOnScreensaver = try container.decode(Bool.self, forKey: .autoLockOnScreensaver)
        lockTimeoutMinutes = try container.decodeIfPresent(Int.self, forKey: .lockTimeoutMinutes)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vaults, forKey: .vaults)
        try container.encode(useKeychain, forKey: .useKeychain)
        try container.encode(autoLockOnSleep, forKey: .autoLockOnSleep)
        try container.encode(autoLockOnScreensaver, forKey: .autoLockOnScreensaver)
        try container.encodeIfPresent(lockTimeoutMinutes, forKey: .lockTimeoutMinutes)
    }
}
