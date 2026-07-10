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
        case openRouterBYOKMetadata = "openrouter-byok-metadata"
        case ollamaBYOKMetadata = "ollama-byok-metadata"
    }

    static func openRouterAPIKey() throws -> String? { try readString(.openRouterAPIKey) }
    static func setOpenRouterAPIKey(_ value: String) throws {
        let existing = try readString(.openRouterAPIKey)
        try write(value, account: .openRouterAPIKey)
        if existing != value {
            try delete(.openRouterBYOKMetadata)
        }
    }
    static func clearOpenRouterAPIKey() throws { try clearProvider(.openRouter) }

    static func ollamaAPIKey() throws -> String? { try readString(.ollamaAPIKey) }
    static func setOllamaAPIKey(_ value: String) throws {
        let existing = try readString(.ollamaAPIKey)
        try write(value, account: .ollamaAPIKey)
        if existing != value {
            try delete(.ollamaBYOKMetadata)
        }
    }
    static func clearOllamaAPIKey() throws { try clearProvider(.ollama) }

    /// Reads whichever credential matches `provider` — the one `CoachController` needs when it
    /// (re)configures the engine.
    static func apiKey(for provider: CoachProviderKind) throws -> String? {
        try readString(keyAccount(for: provider))
    }

    static func hasAPIKey(for provider: CoachProviderKind) -> Bool {
        (((try? apiKey(for: provider)) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    static func byokConnection(for provider: CoachProviderKind) -> CoachProviderConnection? {
        guard let data = try? readData(metadataAccount(for: provider)) else { return nil }
        return try? JSONDecoder().decode(CoachProviderConnection.self, from: data)
    }

    static func saveBYOKGrant(_ grant: BYOKProviderGrant) throws -> CoachProviderConnection {
        try write(grant.apiKey, account: keyAccount(for: grant.provider))

        let connection = CoachProviderConnection(
            provider: grant.provider,
            keyID: grant.keyID,
            keyLabel: grant.keyLabel.isEmpty ? "Default" : grant.keyLabel,
            connectedAt: Date()
        )
        let data = try JSONEncoder().encode(connection)
        try write(data, account: metadataAccount(for: grant.provider))
        return connection
    }

    static func clearProvider(_ provider: CoachProviderKind) throws {
        try delete(keyAccount(for: provider))
        try delete(metadataAccount(for: provider))
    }

    // MARK: - Keychain primitives

    private static func write(_ value: String, account: Account) throws {
        try write(Data(value.utf8), account: account)
    }

    private static func write(_ data: Data, account: Account) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue
        ]
        SecItemDelete(query as CFDictionary)

        // Saving an empty string just clears the stored value — there's nothing useful to keep.
        guard !data.isEmpty else { return }

        query[kSecValueData as String] = data
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

    private static func readString(_ account: Account) throws -> String? {
        guard let data = try readData(account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readData(_ account: Account) throws -> Data? {
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
        return data
    }

    private static func keyAccount(for provider: CoachProviderKind) -> Account {
        switch provider {
        case .openRouter: return .openRouterAPIKey
        case .ollama: return .ollamaAPIKey
        }
    }

    private static func metadataAccount(for provider: CoachProviderKind) -> Account {
        switch provider {
        case .openRouter: return .openRouterBYOKMetadata
        case .ollama: return .ollamaBYOKMetadata
        }
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
