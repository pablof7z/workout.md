import Foundation
import Observation
import Security

/// Owns the app's GitHub credential: stores it in the Keychain, and exposes the minimal identity
/// call (`GET /user`) `GitHubSync` needs to learn the repo owner's login.
///
/// ## Token sourcing today
/// There is no Settings screen yet, so the working path is: call `setToken(_:)` once with a
/// fine-grained PAT (or a classic PAT with `repo` scope) obtained out-of-band — e.g. from
/// `gh auth token`, or a token pasted from https://github.com/settings/tokens. That token is
/// written straight to the Keychain and is never held in a stored property or logged.
///
/// ## Device flow (scaffolded, not wired to any UI yet)
/// `beginDeviceFlow`/`pollDeviceFlow`/`authenticateWithDeviceFlow` implement GitHub's OAuth device
/// flow end-to-end, but they require a *registered GitHub OAuth App* client ID — see
/// `deviceFlowClientID` below. Until that's filled in, calling them will fail against GitHub's API
/// (the `client_id` won't resolve to a real app). The PAT path above is the supported default; the
/// device flow is here so a later Settings screen can offer "Sign in with GitHub" without a token
/// paste, once an OAuth App is registered and its client id dropped in.
@Observable
final class GitHubAuth {
    static let shared = GitHubAuth()

    private let service = "com.workoutmd.github"
    private let account = "github-token"

    /// Whether a token is currently stored. Recomputed at init from the Keychain; not a proxy for
    /// "the token is valid" — call `fetchCurrentUser()` to actually verify it against the API.
    private(set) var isAuthenticated: Bool

    /// The signed-in login, once resolved via `fetchCurrentUser()`. `nil` until that's called
    /// successfully at least once this launch.
    private(set) var login: String?

    init() {
        isAuthenticated = ((try? Self.readToken(service: service, account: account)) ?? nil) != nil
    }

    // MARK: - Token storage (Keychain)

    /// Stores `token` in the Keychain, replacing any existing value. Accessible only after the
    /// first unlock post-boot and only on this device (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
    /// — it never syncs via iCloud Keychain and isn't readable before the user has unlocked once.
    func setToken(_ token: String) throws {
        let data = Data(token.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GitHubAuthError.keychain(status)
        }
        isAuthenticated = true
    }

    /// Removes the stored token (e.g. a future "Sign out" action).
    func clearToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubAuthError.keychain(status)
        }
        isAuthenticated = false
        login = nil
    }

    /// Reads the token fresh from the Keychain on every call — it is never cached in a property,
    /// so there's nothing but this one code path that ever holds it in memory, and it is never
    /// written to a log.
    func currentToken() throws -> String? {
        try Self.readToken(service: service, account: account)
    }

    private static func readToken(service: String, account: String) throws -> String? {
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
            throw GitHubAuthError.keychain(status)
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Identity

    struct GitHubUser: Decodable {
        let login: String
        let id: Int
    }

    /// `GET /user` with the stored token. Confirms the token actually works and resolves the login
    /// (repo owner) so the user never has to type their GitHub username.
    @discardableResult
    func fetchCurrentUser() async throws -> GitHubUser {
        guard let token = try currentToken() else { throw GitHubAuthError.noToken }
        var request = URLRequest(url: GitHubAPI.baseURL.appendingPathComponent("user"))
        GitHubAPI.applyStandardHeaders(to: &request, token: token)
        guard let (data, _) = try await GitHubAPI.send(request) else {
            throw GitHubAuthError.noToken
        }
        let user = try GitHubAPI.decoder.decode(GitHubUser.self, from: data)
        login = user.login
        return user
    }

    // MARK: - Device flow (scaffold — requires a registered OAuth App client id)

    /// TODO: replace with a real GitHub OAuth App's client id (Settings -> Developer settings ->
    /// OAuth Apps, "Device Flow" enabled) to make `authenticateWithDeviceFlow` actually usable. The
    /// device-flow methods below are fully implemented against GitHub's documented protocol; only
    /// this identifier is missing.
    static var deviceFlowClientID = "TODO_REGISTER_GITHUB_OAUTH_APP_CLIENT_ID"

    struct DeviceCodeResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let expiresIn: Int
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case expiresIn = "expires_in"
            case interval = "interval"
        }
    }

    enum DevicePollResult {
        case pending
        case slowDown(newInterval: Int)
        case success(token: String)
        case expiredOrDenied(String)
    }

    /// Step 1 of the device flow: `POST https://github.com/login/device/code`. Returns the
    /// user-facing code/URL to display ("go to github.com/login/device and enter ABCD-1234").
    func beginDeviceFlow(scope: String = "repo") async throws -> DeviceCodeResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.deviceFlowClientID,
            "scope": scope
        ])
        guard let (data, _) = try await GitHubAPI.send(request) else {
            throw GitHubAuthError.deviceFlowFailed("no response")
        }
        return try GitHubAPI.decoder.decode(DeviceCodeResponse.self, from: data)
    }

    /// Step 2: `POST https://github.com/login/oauth/access_token`, polled at `interval` seconds
    /// until the user approves (or the code expires/is denied) on github.com.
    func pollDeviceFlow(deviceCode: String) async throws -> DevicePollResult {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": Self.deviceFlowClientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])
        // This endpoint returns 200 with an `error` field for "pending"/"slow_down", not a non-2xx
        // status, so it's decoded directly rather than through `GitHubAPI.send`'s error path.
        let (data, _) = try await URLSession.shared.data(for: request)

        struct RawResponse: Decodable {
            let accessToken: String?
            let error: String?
            let interval: Int?
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case error, interval
            }
        }
        let raw = try GitHubAPI.decoder.decode(RawResponse.self, from: data)
        if let token = raw.accessToken {
            return .success(token: token)
        }
        switch raw.error {
        case "authorization_pending", nil: return .pending
        case "slow_down": return .slowDown(newInterval: raw.interval ?? 5)
        case "expired_token", "access_denied": return .expiredOrDenied(raw.error ?? "unknown")
        default: return .pending
        }
    }

    /// Drives the two steps above to completion: starts the flow, hands the caller the
    /// user/verification code to display via `onUserCode`, then polls until the user approves,
    /// storing the resulting token via `setToken` on success. Requires `deviceFlowClientID` to be a
    /// real OAuth App id — see the TODO above.
    func authenticateWithDeviceFlow(onUserCode: @escaping (DeviceCodeResponse) -> Void) async throws {
        let start = try await beginDeviceFlow()
        onUserCode(start)
        var interval = UInt64(max(start.interval, 1))
        let deadline = Date().addingTimeInterval(TimeInterval(start.expiresIn))
        while Date() < deadline {
            try await Task.sleep(nanoseconds: interval * 1_000_000_000)
            switch try await pollDeviceFlow(deviceCode: start.deviceCode) {
            case .pending:
                continue
            case .slowDown(let newInterval):
                interval = UInt64(max(newInterval, 1))
            case .success(let token):
                try setToken(token)
                return
            case .expiredOrDenied(let reason):
                throw GitHubAuthError.deviceFlowFailed(reason)
            }
        }
        throw GitHubAuthError.deviceFlowFailed("expired_token")
    }
}

enum GitHubAuthError: Error, LocalizedError {
    case noToken
    case keychain(OSStatus)
    case deviceFlowFailed(String)

    var errorDescription: String? {
        switch self {
        case .noToken: return "No GitHub token is stored. Call GitHubAuth.setToken(_:) first."
        case .keychain(let status): return "Keychain error (OSStatus \(status))."
        case .deviceFlowFailed(let reason): return "GitHub device flow failed: \(reason)."
        }
    }
}
