import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct CoachProviderConnection: Codable, Equatable {
    let provider: CoachProviderKind
    let keyID: String
    let keyLabel: String
    let connectedAt: Date
}

struct BYOKProviderGrant: Equatable {
    let provider: CoachProviderKind
    let apiKey: String
    let keyID: String
    let keyLabel: String
}

extension CoachProviderKind {
    var byokProviderID: String {
        switch self {
        case .openRouter: return "openrouter"
        case .ollama: return "ollama"
        }
    }

    var byokScope: String { "key:\(byokProviderID)" }

    init?(byokProviderID: String) {
        switch byokProviderID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "openrouter": self = .openRouter
        case "ollama": self = .ollama
        default: return nil
        }
    }
}

@MainActor
final class BYOKProviderConnector: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let byokOrigin = URL(string: "https://byok.f7z.io")!
    private static let clientID = "com.workoutmd.prototype"
    private static let appName = "Workout.md"
    private static let callbackScheme = "workoutmd"
    private static let callbackHost = "byok"
    private static let redirectURI = "workoutmd://byok"

    private var session: ASWebAuthenticationSession?

    func connect(providers: [CoachProviderKind]) async throws -> [BYOKProviderGrant] {
        let uniqueProviders = Self.unique(providers)
        guard !uniqueProviders.isEmpty else { throw BYOKProviderError.invalidProvider }

        let verifier = try Self.randomBase64URL(byteCount: 32)
        let state = try Self.randomBase64URL(byteCount: 24)
        let callbackURL = try await authenticate(
            url: Self.authorizationURL(providers: uniqueProviders, verifier: verifier, state: state)
        )
        let code = try Self.authorizationCode(from: callbackURL, expectedState: state)
        let response = try await Self.exchange(code: code, verifier: verifier)
        return try response.grants(expectedProviders: Set(uniqueProviders.map(\.byokProviderID)))
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            if let window = scene.windows.first(where: \.isKeyWindow) {
                return window
            }
        }
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return ASPresentationAnchor(windowScene: scene)
        }
        preconditionFailure("BYOK authentication requires an active window scene.")
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error {
                        continuation.resume(throwing: Self.mapAuthenticationError(error))
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: BYOKProviderError.missingCallback)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            if !session.start() {
                self.session = nil
                continuation.resume(throwing: BYOKProviderError.couldNotStart)
            }
        }
    }

    private static func authorizationURL(providers: [CoachProviderKind], verifier: String, state: String) -> URL {
        var components = URLComponents(url: byokOrigin.appending(path: "authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "app_name", value: appName),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: providers.map(\.byokScope).joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url!
    }

    private static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        guard url.scheme == callbackScheme,
              url.host == callbackHost,
              url.path.isEmpty || url.path == "/" else {
            throw BYOKProviderError.invalidCallback
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = params["error"], !error.isEmpty {
            throw BYOKProviderError.accessDenied(error)
        }
        guard params["state"] == expectedState else {
            throw BYOKProviderError.stateMismatch
        }
        guard let code = params["code"], !code.isEmpty else {
            throw BYOKProviderError.missingCode
        }
        return code
    }

    private static func exchange(code: String, verifier: String) async throws -> BYOKTokenResponse {
        var request = URLRequest(url: byokOrigin.appending(path: "api/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(BYOKTokenRequest(
            code: code,
            codeVerifier: verifier,
            clientID: clientID,
            redirectURI: redirectURI
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BYOKProviderError.invalidTokenResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = (try? JSONDecoder().decode(BYOKErrorResponse.self, from: data).error) ?? "token_exchange_failed"
            throw BYOKProviderError.tokenExchangeFailed(error)
        }
        return try JSONDecoder().decode(BYOKTokenResponse.self, from: data)
    }

    private static func unique(_ providers: [CoachProviderKind]) -> [CoachProviderKind] {
        var seen = Set<String>()
        return providers.filter { seen.insert($0.byokProviderID).inserted }
    }

    private static func mapAuthenticationError(_ error: Error) -> Error {
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return BYOKProviderError.cancelled
        }
        return error
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    private static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw BYOKProviderError.randomGenerationFailed(status) }
        return Data(bytes).base64URLEncodedString()
    }
}

private struct BYOKTokenRequest: Encodable {
    let grantType = "authorization_code"
    let code: String
    let codeVerifier: String
    let clientID: String
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case codeVerifier = "code_verifier"
        case clientID = "client_id"
        case redirectURI = "redirect_uri"
    }
}

private struct BYOKTokenResponse: Decodable {
    let provider: String?
    let apiKey: String?
    let keyID: String?
    let keyLabel: String?
    let providers: [BYOKTokenProvider]?

    enum CodingKeys: String, CodingKey {
        case provider
        case apiKey = "api_key"
        case keyID = "key_id"
        case keyLabel = "key_label"
        case providers
    }

    func grants(expectedProviders: Set<String>) throws -> [BYOKProviderGrant] {
        let responseProviders: [BYOKTokenProvider]
        if let providers {
            responseProviders = providers
        } else {
            responseProviders = [
                BYOKTokenProvider(provider: provider, apiKey: apiKey, keyID: keyID, keyLabel: keyLabel)
            ]
        }

        let grants = try responseProviders.compactMap { tokenProvider -> BYOKProviderGrant? in
            guard let providerID = tokenProvider.provider?.lowercased(), expectedProviders.contains(providerID) else {
                throw BYOKProviderError.invalidTokenResponse
            }
            guard let provider = CoachProviderKind(byokProviderID: providerID),
                  let apiKey = tokenProvider.apiKey,
                  !apiKey.isEmpty else {
                throw BYOKProviderError.invalidTokenResponse
            }
            return BYOKProviderGrant(
                provider: provider,
                apiKey: apiKey,
                keyID: tokenProvider.keyID ?? "",
                keyLabel: (tokenProvider.keyLabel?.isEmpty == false) ? tokenProvider.keyLabel! : "Default"
            )
        }

        guard !grants.isEmpty else { throw BYOKProviderError.noGrantedProviders }
        return grants
    }
}

private struct BYOKTokenProvider: Decodable {
    let provider: String?
    let apiKey: String?
    let keyID: String?
    let keyLabel: String?

    enum CodingKeys: String, CodingKey {
        case provider
        case apiKey = "api_key"
        case keyID = "key_id"
        case keyLabel = "key_label"
    }
}

private struct BYOKErrorResponse: Decodable {
    let error: String
}

private enum BYOKProviderError: LocalizedError {
    case accessDenied(String)
    case cancelled
    case couldNotStart
    case invalidCallback
    case invalidProvider
    case invalidTokenResponse
    case missingCallback
    case missingCode
    case noGrantedProviders
    case randomGenerationFailed(OSStatus)
    case stateMismatch
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Access was denied in BYOK."
        case .cancelled:
            return "BYOK connection was cancelled."
        case .couldNotStart:
            return "Could not open BYOK."
        case .invalidCallback:
            return "BYOK returned through an unexpected callback URL."
        case .invalidProvider:
            return "BYOK provider is missing."
        case .invalidTokenResponse:
            return "BYOK returned an invalid provider token response."
        case .missingCallback:
            return "BYOK did not return to the app."
        case .missingCode:
            return "BYOK did not return an authorization code."
        case .noGrantedProviders:
            return "BYOK did not return any selected provider keys."
        case .randomGenerationFailed(let status):
            return "Could not create BYOK authorization state (\(status))."
        case .stateMismatch:
            return "BYOK returned an authorization response with an invalid state."
        case .tokenExchangeFailed(let reason):
            return "BYOK token exchange failed: \(reason)."
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
