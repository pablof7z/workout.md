import Foundation

/// Keeps a private GitHub repo in sync with the app's local workout history, using only the GitHub
/// REST (Contents) API over `URLSession` — no git library on device. Every operation below is one
/// authenticated HTTPS call:
///
/// - `ensureRepo(name:)` — `GET /repos/{owner}/{repo}`, creating it via `POST /user/repos` (private,
///   auto-initialized) if it doesn't exist yet.
/// - `commitSession(markdown:path:message:)` — `GET` the file (to get its `sha`, if it exists) then
///   `PUT /repos/{owner}/{repo}/contents/{path}`. Idempotent: if the fetched content already matches,
///   no write happens.
/// - `pull()` — `GET /repos/{owner}/{repo}/commits`, diffs against the last-synced sha, and fetches
///   the content of any changed `sessions/*.md` (or `README.md`) file from commits *not* authored by
///   this app's own sync identity — i.e. changes the user made outside the app (editing on
///   github.com, or `git push` from a laptop).
///
/// Path convention: one Markdown file per workday, `sessions/YYYY-MM-DD-<slugified-name>.md`. A
/// `README.md` at the repo root is kept as a running index of session files.
final class GitHubSync {
    struct ChangedFile: Identifiable, Equatable {
        var id: String { "\(commitSHA)-\(path)" }
        let path: String
        let content: String
        let sha: String
        let commitSHA: String
        let commitMessage: String
        let commitDate: Date
    }

    enum CommitOutcome: Equatable {
        case created
        case updated
        case unchanged
    }

    enum SyncError: Error, LocalizedError {
        case notAuthenticated
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "No GitHub token is stored. Call GitHubAuth.setToken(_:) first."
            case .invalidResponse: return "Unexpected response shape from the GitHub API."
            }
        }
    }

    /// The committer identity stamped on every commit this app makes (via the Contents API's
    /// optional `committer` field). `pull()` uses this to tell "our own writes" apart from changes
    /// the user made some other way — anything committed under a different name is external.
    static let botCommitterName = "Workout.md Sync"
    static let botCommitterEmail = "sync@workout.md.app"

    /// Called with any external (non-app-authored) file changes discovered by `pull()`. This is the
    /// hook point for the coach: "there are new commits, let me see what changed." Wiring the coach
    /// review itself is a later workstream — for now this just delivers the changed files.
    var onExternalChanges: (([ChangedFile]) -> Void)?

    private(set) var repoName: String
    private let auth: GitHubAuth
    private let session: URLSession
    private let defaults: UserDefaults
    private var cachedOwner: String?

    init(
        auth: GitHubAuth = .shared,
        repoName: String = "workout-log",
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.auth = auth
        self.repoName = repoName
        self.session = session
        self.defaults = defaults
    }

    /// Updates which repo this instance targets for future sync calls — e.g. the user changed the
    /// repo name field in Settings. Takes effect on the next `ensureRepo`/`commitSession`/`pull`
    /// call; does not itself make a network call.
    func setRepoName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != repoName else { return }
        repoName = trimmed
    }

    // MARK: - Repo lifecycle

    struct RepoInfo: Decodable {
        let name: String
        let fullName: String
        let defaultBranch: String
        let owner: Owner
        let `private`: Bool

        struct Owner: Decodable { let login: String }

        enum CodingKeys: String, CodingKey {
            case name, owner, `private`
            case fullName = "full_name"
            case defaultBranch = "default_branch"
        }
    }

    /// Ensures the sync repo exists, creating it as a **private** repo if `GET` 404s. Pass `name` to
    /// switch which repo this instance targets (e.g. for testing against a scratch repo); omit it to
    /// use the repo name this instance was configured with.
    @discardableResult
    func ensureRepo(name: String? = nil) async throws -> RepoInfo {
        if let name, name != repoName {
            repoName = name
        }
        let owner = try await resolveOwner()
        let token = try requireToken()

        var request = URLRequest(url: GitHubAPI.baseURL.appendingPathComponent("repos/\(owner)/\(repoName)"))
        GitHubAPI.applyStandardHeaders(to: &request, token: token)
        if let (data, _) = try await GitHubAPI.send(request, session: session, allow404: true) {
            return try GitHubAPI.decoder.decode(RepoInfo.self, from: data)
        }
        return try await createRepo(token: token)
    }

    private func createRepo(token: String) async throws -> RepoInfo {
        var request = URLRequest(url: GitHubAPI.baseURL.appendingPathComponent("user/repos"))
        request.httpMethod = "POST"
        GitHubAPI.applyStandardHeaders(to: &request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": repoName,
            "private": true,
            "auto_init": true,
            "description": "Workout.md log"
        ])
        guard let (data, _) = try await GitHubAPI.send(request, session: session) else {
            throw SyncError.invalidResponse
        }
        return try GitHubAPI.decoder.decode(RepoInfo.self, from: data)
    }

    // MARK: - Committing a session

    /// Writes `markdown` to `path` (creating or updating it) with commit message `message`.
    /// Idempotent — if `path` already holds identical content, this is a no-op that returns
    /// `.unchanged` without any write call. Also best-effort updates the `README.md` index; a
    /// failure there does not fail the session commit itself.
    @discardableResult
    func commitSession(markdown: String, path: String, message: String) async throws -> CommitOutcome {
        try await ensureRepo()
        let owner = try await resolveOwner()
        let token = try requireToken()

        let existing = try await getFile(owner: owner, path: path, token: token)
        if let existing, existing.decodedText == markdown {
            return .unchanged
        }

        _ = try await putFile(owner: owner, path: path, content: markdown, message: message, sha: existing?.sha, token: token)
        try? await updateReadmeIndex(owner: owner, token: token, newPath: path)
        return existing == nil ? .created : .updated
    }

    /// `sessions/YYYY-MM-DD-<slug>.md` — one file per workday per workout name.
    static func sessionPath(for record: WorkoutRecord) -> String {
        sessionPath(date: record.date, workoutName: record.name)
    }

    static func sessionPath(date: Date, workoutName: String) -> String {
        "sessions/\(dayFormatter.string(from: date))-\(slugify(workoutName)).md"
    }

    private static func slugify(_ text: String) -> String {
        var result = ""
        var lastWasDash = false
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()

    // MARK: - README index

    private static let defaultReadme = """
    # Workout.md Log

    Private, app-managed log of workout sessions. Each file under `sessions/` is a Markdown \
    snapshot of one workday's session. This file is a running index, kept up to date by the app.

    Feel free to edit anything in this repo directly (on github.com, or with `git`) — Workout.md \
    periodically pulls and treats any commit it didn't author itself as an external change for the \
    in-app coach to review.

    ## Sessions
    """

    private func updateReadmeIndex(owner: String, token: String, newPath: String) async throws {
        let existing = try await getFile(owner: owner, path: "README.md", token: token)
        var lines = (existing?.decodedText ?? Self.defaultReadme).components(separatedBy: "\n")
        let bullet = "- [\(newPath)](\(newPath))"
        guard !lines.contains(bullet) else { return }
        lines.append(bullet)
        let updated = lines.joined(separator: "\n")
        _ = try await putFile(
            owner: owner,
            path: "README.md",
            content: updated,
            message: "Index \(newPath)",
            sha: existing?.sha,
            token: token
        )
    }

    // MARK: - Contents API primitives

    struct ContentsResponse: Decodable, Equatable {
        let sha: String
        let path: String
        let content: String?
        let encoding: String?

        var decodedText: String? {
            guard let content else { return nil }
            guard encoding == "base64" else { return content }
            let cleaned = content.replacingOccurrences(of: "\n", with: "")
            guard let data = Data(base64Encoded: cleaned) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        static func == (lhs: ContentsResponse, rhs: ContentsResponse) -> Bool {
            lhs.sha == rhs.sha && lhs.path == rhs.path
        }
    }

    /// `GET /repos/{owner}/{repo}/contents/{path}`, returning `nil` on a 404 (file doesn't exist).
    private func getFile(owner: String, path: String, ref: String? = nil, token: String) async throws -> ContentsResponse? {
        let url = GitHubAPI.baseURL.appendingPathComponent("repos/\(owner)/\(repoName)/contents/\(path)")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if let ref {
            components.queryItems = [URLQueryItem(name: "ref", value: ref)]
        }
        var request = URLRequest(url: components.url!)
        GitHubAPI.applyStandardHeaders(to: &request, token: token)
        guard let (data, _) = try await GitHubAPI.send(request, session: session, allow404: true) else {
            return nil
        }
        return try GitHubAPI.decoder.decode(ContentsResponse.self, from: data)
    }

    private struct ContentsPutResponse: Decodable {
        let content: FileInfo
        let commit: CommitRef
        struct FileInfo: Decodable { let sha: String }
        struct CommitRef: Decodable { let sha: String }
    }

    /// `PUT /repos/{owner}/{repo}/contents/{path}` — creates the file if `sha` is `nil`, updates it
    /// (must supply the current `sha`) otherwise. Stamps `committer` with the bot identity above so
    /// `pull()` can recognize this as an app-made commit.
    @discardableResult
    private func putFile(owner: String, path: String, content: String, message: String, sha: String?, token: String) async throws -> ContentsPutResponse {
        var request = URLRequest(url: GitHubAPI.baseURL.appendingPathComponent("repos/\(owner)/\(repoName)/contents/\(path)"))
        request.httpMethod = "PUT"
        GitHubAPI.applyStandardHeaders(to: &request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Committer: Encodable { let name: String; let email: String }
        struct Body: Encodable {
            let message: String
            let content: String
            let sha: String?
            let committer: Committer
        }
        let body = Body(
            message: message,
            content: Data(content.utf8).base64EncodedString(),
            sha: sha,
            committer: Committer(name: Self.botCommitterName, email: Self.botCommitterEmail)
        )
        request.httpBody = try GitHubAPI.encoder.encode(body)

        guard let (data, _) = try await GitHubAPI.send(request, session: session) else {
            throw SyncError.invalidResponse
        }
        return try GitHubAPI.decoder.decode(ContentsPutResponse.self, from: data)
    }

    /// `DELETE /repos/{owner}/{repo}/contents/{path}` — used by the API-verification harness to
    /// clean up its scratch file; not otherwise exercised by the app's normal sync flow.
    func deleteFile(path: String, message: String) async throws {
        let owner = try await resolveOwner()
        let token = try requireToken()
        guard let existing = try await getFile(owner: owner, path: path, token: token) else {
            return // already gone
        }
        var request = URLRequest(url: GitHubAPI.baseURL.appendingPathComponent("repos/\(owner)/\(repoName)/contents/\(path)"))
        request.httpMethod = "DELETE"
        GitHubAPI.applyStandardHeaders(to: &request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Committer: Encodable { let name: String; let email: String }
        struct Body: Encodable {
            let message: String
            let sha: String
            let committer: Committer
        }
        let body = Body(message: message, sha: existing.sha, committer: Committer(name: Self.botCommitterName, email: Self.botCommitterEmail))
        request.httpBody = try GitHubAPI.encoder.encode(body)

        _ = try await GitHubAPI.send(request, session: session)
    }

    // MARK: - Pull / ingest external changes

    /// The sha of the most-recent commit this instance has already processed. Persisted per-repo so
    /// a relaunch doesn't re-ingest history that was already seen.
    private var lastSyncedShaKey: String { "com.workoutmd.sync.lastSyncedSha.\(repoName)" }

    private(set) var lastSyncedSha: String? {
        get { defaults.string(forKey: lastSyncedShaKey) }
        set { defaults.set(newValue, forKey: lastSyncedShaKey) }
    }

    private struct CommitSummary: Decodable {
        let sha: String
        let commit: CommitDetail

        struct CommitDetail: Decodable {
            let message: String
            let committer: GitIdentity?
        }
        struct GitIdentity: Decodable {
            let name: String
            let date: Date
        }
    }

    private struct CommitDetailResponse: Decodable {
        let sha: String
        let commit: CommitSummary.CommitDetail
        let files: [CommitFile]

        struct CommitFile: Decodable {
            let filename: String
            let status: String
        }
    }

    /// Lists recent commits, finds any since the last sync that this app didn't author itself, and
    /// fetches the content of the `sessions/*.md`/`README.md` files those commits touched. Advances
    /// `lastSyncedSha` on success (even if nothing new was found) so subsequent calls don't re-scan
    /// the same range. Calls `onExternalChanges` with any non-empty result before returning it.
    @discardableResult
    func pull() async throws -> [ChangedFile] {
        try await ensureRepo()
        let owner = try await resolveOwner()
        let token = try requireToken()

        let url = GitHubAPI.baseURL.appendingPathComponent("repos/\(owner)/\(repoName)/commits")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        var request = URLRequest(url: components.url!)
        GitHubAPI.applyStandardHeaders(to: &request, token: token)

        guard let (data, _) = try await GitHubAPI.send(request, session: session, allow404: true) else {
            return [] // repo has no commits yet (shouldn't happen post auto_init, but be defensive)
        }
        let commits = try GitHubAPI.decoder.decode([CommitSummary].self, from: data)
        guard let latestSha = commits.first?.sha else { return [] }
        guard latestSha != lastSyncedSha else { return [] } // already caught up

        let newCommits: [CommitSummary]
        if let lastSyncedSha, let cutoffIndex = commits.firstIndex(where: { $0.sha == lastSyncedSha }) {
            newCommits = Array(commits[0..<cutoffIndex]) // strictly newer than what we've seen
        } else if lastSyncedSha == nil {
            // First run: nothing to ingest yet, just establish a baseline so future pulls diff from here.
            newCommits = []
        } else {
            // The last-synced sha scrolled off this page of history; ingest what we can see rather
            // than silently drop it.
            newCommits = commits
        }

        // Anything not stamped with our own committer identity is a change made outside the app.
        let externalCommits = newCommits.filter { $0.commit.committer?.name != Self.botCommitterName }

        var changed: [ChangedFile] = []
        for summary in externalCommits.reversed() { // oldest external change first
            if let files = try? await fetchChangedSessionFiles(owner: owner, commitSHA: summary.sha, token: token) {
                changed.append(contentsOf: files)
            }
        }

        lastSyncedSha = latestSha
        if !changed.isEmpty {
            onExternalChanges?(changed)
        }
        return changed
    }

    private func fetchChangedSessionFiles(owner: String, commitSHA: String, token: String) async throws -> [ChangedFile] {
        var request = URLRequest(url: GitHubAPI.baseURL.appendingPathComponent("repos/\(owner)/\(repoName)/commits/\(commitSHA)"))
        GitHubAPI.applyStandardHeaders(to: &request, token: token)
        guard let (data, _) = try await GitHubAPI.send(request, session: session, allow404: true) else {
            return []
        }
        let detail = try GitHubAPI.decoder.decode(CommitDetailResponse.self, from: data)

        var results: [ChangedFile] = []
        for file in detail.files where file.status != "removed" {
            guard file.filename.hasPrefix("sessions/") || file.filename == "README.md" else { continue }
            guard let contents = try await getFile(owner: owner, path: file.filename, ref: commitSHA, token: token),
                  let text = contents.decodedText else { continue }
            results.append(ChangedFile(
                path: file.filename,
                content: text,
                sha: contents.sha,
                commitSHA: detail.sha,
                commitMessage: detail.commit.message,
                commitDate: detail.commit.committer?.date ?? .now
            ))
        }
        return results
    }

    // MARK: - Offline retry queue

    private struct PendingCommit: Codable {
        var id = UUID()
        let path: String
        let markdown: String
        let message: String
        var attempts: Int = 0
    }

    private var pendingCommitsURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkoutMD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending-commits-\(repoName).json")
    }

    private func loadPendingCommits() -> [PendingCommit] {
        guard let data = try? Data(contentsOf: pendingCommitsURL) else { return [] }
        return (try? JSONDecoder().decode([PendingCommit].self, from: data)) ?? []
    }

    private func savePendingCommits(_ commits: [PendingCommit]) {
        guard let data = try? JSONEncoder().encode(commits) else { return }
        try? data.write(to: pendingCommitsURL, options: .atomic)
    }

    /// Queues a commit that failed (typically: offline) so `flushPendingCommits()` can retry it
    /// later. De-dupes on `path` — a newer attempt for the same file supersedes an older queued one
    /// rather than piling up.
    func enqueueRetry(markdown: String, path: String, message: String) {
        var pending = loadPendingCommits()
        pending.removeAll { $0.path == path }
        pending.append(PendingCommit(path: path, markdown: markdown, message: message))
        savePendingCommits(pending)
    }

    var pendingCommitCount: Int { loadPendingCommits().count }

    /// Retries anything queued by `enqueueRetry`. Safe to call opportunistically (on foreground, on
    /// every `pull()`) — each retry goes through the same idempotent `commitSession`, so a commit
    /// that actually landed despite a client-side error (e.g. the response was lost after a
    /// successful write) is a no-op rather than a duplicate.
    @discardableResult
    func flushPendingCommits() async -> Int {
        let pending = loadPendingCommits()
        guard !pending.isEmpty else { return 0 }

        var succeeded = 0
        var stillPending: [PendingCommit] = []
        for var item in pending {
            do {
                _ = try await commitSession(markdown: item.markdown, path: item.path, message: item.message)
                succeeded += 1
            } catch {
                item.attempts += 1
                stillPending.append(item)
            }
        }
        savePendingCommits(stillPending)
        return succeeded
    }

    // MARK: - Helpers

    private func resolveOwner() async throws -> String {
        if let cachedOwner { return cachedOwner }
        let user = try await auth.fetchCurrentUser()
        cachedOwner = user.login
        return user.login
    }

    private func requireToken() throws -> String {
        guard let token = try auth.currentToken() else { throw SyncError.notAuthenticated }
        return token
    }
}
