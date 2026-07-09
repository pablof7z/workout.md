import Foundation
import Security

/// Keychain-only storage for the coach's Nostr identity (`nsec1...`) used to join the user's
/// tenex-edge fabric (see `FabricController`). Mirrors `CoachSecrets`/`GitHubAuth`'s Keychain pattern
/// exactly: the nsec is never held in a stored property beyond the live `NostrCoach` instance it's
/// imported into, never written to `UserDefaults`, never logged, and is only readable after the
/// device's first unlock post-boot (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), on this
/// device only (no iCloud Keychain sync).
enum FabricSecrets {
    private static let service = "com.workoutmd.fabric"
    private static let account = "coach-nsec"

    static func nsec() throws -> String? { try read() }
    static func setNsec(_ value: String) throws { try write(value) }
    static func clearNsec() throws { try delete() }

    // MARK: - Keychain primitives (identical shape to `CoachSecrets`)

    private static func write(_ value: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        guard !value.isEmpty else { return }

        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw FabricSecretsError.keychain(status) }
    }

    private static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FabricSecretsError.keychain(status)
        }
    }

    private static func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw FabricSecretsError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }
}

enum FabricSecretsError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Keychain error (OSStatus \(status))."
        }
    }
}
