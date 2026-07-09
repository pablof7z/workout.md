import Foundation

/// Low-level plumbing shared by `GitHubAuth` and `GitHubSync`: the GitHub REST API base URL,
/// standard headers, JSON coding, and a single `send(_:)` entry point that every request in this
/// module routes through so rate-limit backoff and error decoding live in one place.
///
/// Deliberately just `URLSession` + `Codable` — no git library. Every operation the app needs
/// (create a repo, read/write a file, list commits) has a plain REST endpoint, so there's no need
/// to link libgit2/SwiftGit2 or manage an on-device git working tree.
enum GitHubAPI {
    static let baseURL = URL(string: "https://api.github.com")!

    /// Sets the headers GitHub's REST API expects on every authenticated call. The token is passed
    /// in by the caller (read fresh from Keychain per-request) — this function never persists or
    /// logs it.
    static func applyStandardHeaders(to request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("WorkoutMD-iOS", forHTTPHeaderField: "User-Agent")
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = JSONEncoder()

    /// A non-2xx GitHub response, with any rate-limit backoff hint already extracted from headers.
    struct HTTPStatusError: Error, LocalizedError {
        let statusCode: Int
        let body: String
        var retryAfter: TimeInterval?

        var errorDescription: String? {
            "GitHub API returned HTTP \(statusCode)\(body.isEmpty ? "" : ": \(body)")"
        }
    }

    /// Reads `Retry-After` if present, else — for a 403 that's actually the secondary/primary rate
    /// limit rather than a permissions error — derives a wait time from `X-RateLimit-Reset`.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        if let header = response.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(header) {
            return seconds
        }
        if response.statusCode == 403,
           response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
           let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let epoch = TimeInterval(reset) {
            return max(0, epoch - Date().timeIntervalSince1970)
        }
        return nil
    }

    /// Sends `request`, transparently retrying on 403/429 rate-limiting by sleeping for the
    /// server-provided backoff (bounded to 60s) up to `maxAttempts` times. Pass `allow404: true` to
    /// get `nil` back for a 404 rather than a thrown error — used for "does this file/repo exist
    /// yet?" existence checks, where a 404 is an expected, non-error outcome.
    static func send(
        _ request: URLRequest,
        session: URLSession = .shared,
        allow404: Bool = false,
        maxAttempts: Int = 3
    ) async throws -> (Data, HTTPURLResponse)? {
        var attempt = 0
        while true {
            attempt += 1
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if allow404, http.statusCode == 404 {
                return nil
            }
            if (200...299).contains(http.statusCode) {
                return (data, http)
            }
            let retry = retryAfter(from: http)
            if (http.statusCode == 403 || http.statusCode == 429), attempt < maxAttempts, let retry {
                try await Task.sleep(nanoseconds: UInt64(min(retry, 60)) * 1_000_000_000)
                continue
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HTTPStatusError(statusCode: http.statusCode, body: body, retryAfter: retry)
        }
    }
}
