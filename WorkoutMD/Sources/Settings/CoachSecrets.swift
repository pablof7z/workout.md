import Foundation
import Security

/// Keychain-only storage for coach provider credentials: the OpenRouter API key, and an optional
/// Ollama bearer token (for a protected/remote Ollama deployment — the common local case leaves
/// this unset and `ProviderConfig.Ollama.api_key` goes through as `nil`).
///
/// Mirrors `GitHubAuth`'s Keychain pattern exactly: a value is never cached in a stored property,
/// never logged, and is only readable after the device's first unlock post-boot
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), on this device only (no iCloud Keychain
/// sync).
enum CoachSecrets {
    private static let service = "com.workoutmd.coach"

    private enum Account: String {
        case openRouterAPIKey = "openrouter-api-key"
        case ollamaAPIKey = "ollama-api-key"
    }

    static func openRouterAPIKey() throws -> String? { try read(.openRouterAPIKey) }
    static func setOpenRouterAPIKey(_ value: String) throws { try write(value, account: .openRouterAPIKey) }
    static func clearOpenRouterAPIKey() throws { try delete(.openRouterAPIKey) }

    static func ollamaAPIKey() throws -> String? { try read(.ollamaAPIKey) }
    static func setOllamaAPIKey(_ value: String) throws { try write(value, account: .ollamaAPIKey) }
    static func clearOllamaAPIKey() throws { try delete(.ollamaAPIKey) }

    /// Reads whichever credential matches `provider` — the one `CoachController` needs when it
    /// (re)configures the engine.
    static func apiKey(for provider: CoachProviderKind) throws -> String? {
        switch provider {
        case .openRouter: return try openRouterAPIKey()
        case .ollama: return try ollamaAPIKey()
        }
    }

    // MARK: - Keychain primitives

    private static func write(_ value: String, account: Account) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        // Saving an empty string just clears the stored value — there's nothing useful to keep.
        guard !value.isEmpty else { return }

        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CoachSecretsError.keychain(status) }
    }

    private static func delete(_ account: Account) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CoachSecretsError.keychain(status)
        }
    }

    private static func read(_ account: Account) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CoachSecretsError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }
}

enum CoachSecretsError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Keychain error (OSStatus \(status))."
        }
    }
}
