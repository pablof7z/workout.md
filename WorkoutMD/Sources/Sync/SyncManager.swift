import Foundation
import Observation

/// Current sync activity, for a (future) Settings/status UI and the debug affordance in
/// `HistoryView` today.
enum SyncStatus: Equatable {
    case idle
    case syncing
    case unavailable
    case error(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .syncing: return "Syncing…"
        case .unavailable: return "Unavailable — sign in to iCloud"
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

    // MARK: - iCloud mirror
    //
    // Fully independent of the GitHub properties/methods above: separate status, separate
    // last-synced timestamp, gated by its own `AppSettings.icloudSyncEnabled` toggle rather than
    // GitHub auth. Both are just separate mirrors of the same rendered Markdown — see `ICloudSync`'s
    // doc comment.

    let icloud: ICloudSync
    private(set) var icloudStatus: SyncStatus = .idle
    private(set) var lastICloudSyncedAt: Date?
    var onICloudExternalChanges: (([ICloudSync.ChangedFile]) -> Void)?

    var isICloudAvailable: Bool { icloud.isAvailable }

    let auth: GitHubAuth
    let sync: GitHubSync

    private let pullInterval: TimeInterval
    private var pullTimer: Timer?

    var isAuthenticated: Bool { auth.isAuthenticated }
    var pendingCommitCount: Int { sync.pendingCommitCount }

    init(auth: GitHubAuth = .shared, sync: GitHubSync? = nil, icloud: ICloudSync? = nil, pullInterval: TimeInterval = 15 * 60) {
        self.auth = auth
        self.sync = sync ?? GitHubSync(auth: auth)
        self.icloud = icloud ?? ICloudSync()
        self.pullInterval = pullInterval
        self.sync.onExternalChanges = { [weak self] changes in
            self?.lastExternalChanges = changes
            self?.onExternalChanges?(changes)
        }
        self.icloud.onExternalChanges = { [weak self] changes in
            self?.onICloudExternalChanges?(changes)
        }
    }

    // MARK: - App lifecycle hooks

    /// Call from `.onAppear`/`scenePhase == .active`: pulls immediately (GitHub + iCloud), (re)starts
    /// the periodic GitHub pull timer, and — if the iCloud toggle is on — starts the live
    /// `NSMetadataQuery` watch so an edit made on another device flows in while foregrounded.
    func appDidBecomeActive() {
        if AppSettings.shared.icloudSyncEnabled {
            icloud.startObserving()
        }
        Task { await pullNow() }
        pullTimer?.invalidate()
        pullTimer = Timer.scheduledTimer(withTimeInterval: pullInterval, repeats: true) { [weak self] _ in
            Task { await self?.pullNow() }
        }
    }

    /// Call from `scenePhase == .background`: stops the GitHub pull timer and the iCloud
    /// `NSMetadataQuery` watch so neither fires while suspended.
    func appDidEnterBackground() {
        icloud.stopObserving()
        pullTimer?.invalidate()
        pullTimer = nil
    }

    // MARK: - Commit hook (wire into the Done/save flow)

    /// Commits a just-finished session's Markdown to every enabled sync target. Call this right
    /// after the session is saved to SwiftData (see `WorkoutMDApp.saveToHistory`). Each target is
    /// independent: the iCloud mirror (gated by `AppSettings.icloudSyncEnabled`) runs regardless of
    /// GitHub auth state, and a GitHub failure doesn't undo or block the iCloud write (or vice
    /// versa). Silently does nothing for GitHub if no token is stored yet, and nothing for iCloud if
    /// its toggle is off — both syncs are opt-in.
    @discardableResult
    func commitSession(_ record: WorkoutRecord) async -> Bool {
        let markdown = MarkdownGenerator.renderSession(record)

        await commitSessionToICloud(record, markdown: markdown)

        guard isAuthenticated else { return false }
        status = .syncing
        let path = GitHubSync.sessionPath(for: record)
        let message = "Log \(record.name) — \(path)"
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

    private func commitSessionToICloud(_ record: WorkoutRecord, markdown: String) async {
        guard AppSettings.shared.icloudSyncEnabled else { return }
        icloudStatus = .syncing
        do {
            let filename = GitHubSync.sessionFileName(for: record)
            _ = try await icloud.writeSession(markdown: markdown, filename: filename)
            let plan = MarkdownGenerator.renderPlan(name: MockWorkout.name, goal: MockWorkout.goal, blocks: MockWorkout.blocks)
            try? await icloud.writePlan(markdown: plan)
            lastICloudSyncedAt = .now
            icloudStatus = .idle
        } catch ICloudSync.ICloudSyncError.unavailable {
            icloudStatus = .unavailable
        } catch {
            icloudStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Pull

    /// Pulls recent commits, ingesting any external changes and retrying anything queued from a
    /// previously-failed commit. Safe to call anytime (foreground, timer, or the debug button) —
    /// every step is idempotent.
    func pullNow() async {
        await pullICloudNow()

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

    /// Pulls the iCloud mirror only — independent of GitHub auth/pull above, gated by its own
    /// `AppSettings.icloudSyncEnabled` toggle. Exposed separately (rather than folded silently into
    /// `pullNow()`) so Settings' "Sync iCloud now" button and the toggle's on-change handler can
    /// trigger just this half and see its own status update immediately.
    @discardableResult
    func pullICloudNow() async -> Bool {
        guard AppSettings.shared.icloudSyncEnabled else { return false }
        icloudStatus = .syncing
        do {
            _ = try await icloud.pull()
            lastICloudSyncedAt = .now
            icloudStatus = .idle
            return true
        } catch ICloudSync.ICloudSyncError.unavailable {
            icloudStatus = .unavailable
            return false
        } catch {
            icloudStatus = .error(error.localizedDescription)
            return false
        }
    }

    /// Call from the Settings toggle's `onChange` so flipping it on/off takes effect immediately
    /// (starts/stops the live watch and does an immediate pull) rather than waiting for the next
    /// foreground/session-save.
    func icloudToggleChanged(enabled: Bool) {
        if enabled {
            icloud.startObserving()
            Task { await pullICloudNow() }
        } else {
            icloud.stopObserving()
            icloudStatus = .idle
        }
    }
}
