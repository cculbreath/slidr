import Foundation
import Security

struct KeychainService {
    static let xaiAPIKeyName = "com.physicscloud.slidr.xai-api-key"
    static let groqAPIKeyName = "com.physicscloud.slidr.groq-api-key"

    enum KeychainError: LocalizedError {
        case saveFailed(OSStatus)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Keychain save failed with status \(status)"
            case .encodingFailed:
                return "Failed to encode value for keychain storage"
            }
        }
    }

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.physicscloud.slidr",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.physicscloud.slidr",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.physicscloud.slidr",
        ]

        SecItemDelete(query as CFDictionary)
    }

    static func exists(key: String) -> Bool {
        load(key: key) != nil
    }
}
