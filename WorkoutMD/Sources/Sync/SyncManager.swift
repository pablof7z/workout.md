import Foundation
import Observation

/// Current sync activity, for a (future) Settings/status UI and the debug affordance in
/// `HistoryView` today.
enum SyncStatus: Equatable {
    case idle
    case syncing
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .syncing: return "Syncing…"
        case .error(let message): return "Error: \(message)"
        }
    }
}

/// Wires `GitHubSync` into the app's lifecycle: commits a session when one finishes, and pulls
/// periodically (on foreground + a repeating timer) so the in-app coach can eventually be told
/// "there are new commits, here's what changed." This is the single object the rest of the app
/// talks to — `GitHubSync`/`GitHubAuth` are implementation details behind it.
///
/// No Settings screen yet: `isAuthenticated`, `status`, `lastSyncedAt`, and `syncNow()` /
/// `pullNow()` are exposed so a minimal debug affordance (see `HistoryView`) can trigger and
/// observe sync without one.
@Observable
final class SyncManager {
    static let shared = SyncManager()

    private(set) var status: SyncStatus = .idle
    private(set) var lastSyncedAt: Date?
    private(set) var lastExternalChanges: [GitHubSync.ChangedFile] = []

    /// The coach-review hook: fires whenever `pull()` finds commits this app didn't make itself.
    /// Wiring an actual review UI/flow is a later workstream — this closure is the plug point.
    var onExternalChanges: (([GitHubSync.ChangedFile]) -> Void)?

    let auth: GitHubAuth
    let sync: GitHubSync

    private let pullInterval: TimeInterval
    private var pullTimer: Timer?

    var isAuthenticated: Bool { auth.isAuthenticated }
    var pendingCommitCount: Int { sync.pendingCommitCount }

    init(auth: GitHubAuth = .shared, sync: GitHubSync? = nil, pullInterval: TimeInterval = 15 * 60) {
        self.auth = auth
        self.sync = sync ?? GitHubSync(auth: auth)
        self.pullInterval = pullInterval
        self.sync.onExternalChanges = { [weak self] changes in
            self?.lastExternalChanges = changes
            self?.onExternalChanges?(changes)
        }
    }

    // MARK: - App lifecycle hooks

    /// Call from `.onAppear`/`scenePhase == .active`: pulls immediately and (re)starts the periodic
    /// pull timer.
    func appDidBecomeActive() {
        Task { await pullNow() }
        pullTimer?.invalidate()
        pullTimer = Timer.scheduledTimer(withTimeInterval: pullInterval, repeats: true) { [weak self] _ in
            Task { await self?.pullNow() }
        }
    }

    /// Call from `scenePhase == .background`: stops the timer so it doesn't fire while suspended.
    func appDidEnterBackground() {
        pullTimer?.invalidate()
        pullTimer = nil
    }

    // MARK: - Commit hook (wire into the Done/save flow)

    /// Commits a just-finished session's Markdown. Call this right after the session is saved to
    /// SwiftData (see `WorkoutMDApp.saveToHistory`). Silently does nothing if no token is stored
    /// yet — sync is opt-in until a token is set.
    @discardableResult
    func commitSession(_ record: WorkoutRecord) async -> Bool {
        guard isAuthenticated else { return false }
        status = .syncing
        let path = GitHubSync.sessionPath(for: record)
        let markdown = MarkdownGenerator.renderSession(record)
        let message = "Log \(record.name) — \(GitHubSync.sessionPath(for: record))"
        do {
            _ = try await sync.commitSession(markdown: markdown, path: path, message: message)
            lastSyncedAt = .now
            status = .idle
            return true
        } catch {
            status = .error(error.localizedDescription)
            // Likely offline or transient — queue it so the next pull/foreground retries it rather
            // than losing the session's write.
            sync.enqueueRetry(markdown: markdown, path: path, message: message)
            return false
        }
    }

    // MARK: - Pull

    /// Pulls recent commits, ingesting any external changes and retrying anything queued from a
    /// previously-failed commit. Safe to call anytime (foreground, timer, or the debug button) —
    /// every step is idempotent.
    func pullNow() async {
        guard isAuthenticated else { return }
        status = .syncing
        do {
            _ = try await sync.flushPendingCommits()
            let changes = try await sync.pull()
            if !changes.isEmpty {
                lastExternalChanges = changes
            }
            lastSyncedAt = .now
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}
