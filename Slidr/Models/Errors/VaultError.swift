import Foundation

enum VaultError: LocalizedError {
    case failedToCreate(String)
    case failedToMount(String)
    case failedToUnmount(String)
    case incorrectPassword
    case vaultNotFound(String)
    case unsupportedFileSystem(String)
    case manifestCorrupted
    case vaultAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .failedToCreate(let reason):
            "Failed to create vault: \(reason)"
        case .failedToMount(let reason):
            "Failed to mount vault: \(reason)"
        case .failedToUnmount(let reason):
            "Failed to unmount vault: \(reason)"
        case .incorrectPassword:
            "Incorrect password"
        case .vaultNotFound(let name):
            "Vault not found: \(name)"
        case .unsupportedFileSystem(let fs):
            "Filesystem \(fs) doesn't support encrypted vaults. Use APFS or HFS+."
        case .manifestCorrupted:
            "Vault manifest is corrupted"
        case .vaultAlreadyExists(let name):
            "A vault named '\(name)' already exists"
        }
    }
}
