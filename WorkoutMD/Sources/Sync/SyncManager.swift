import Foundation
import Observation
import SwiftData

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
    /// Re-exposed (in addition to being consumed below) so a future UI can still observe raw external
    /// changes directly if it wants to, independent of the coach's own review turn.
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
            // M2: this is the "onExternalChanges consumer" — hand the changed Markdown to the coach
            // for an actual review turn (not just ingestion) via the background `CoachController`
            // singleton, since `SyncManager` itself has no live `WorkoutSession`/transcript to attach
            // one to. See `CoachController.reviewExternalChanges` and `CoachReviewStore`.
            CoachController.shared.reviewExternalChanges(changes)
            // domain-primitives.md §11: the coach-review turn above is READ-only (a note about what
            // it saw) — it does not itself reconcile SwiftData. Route the same changed files through
            // `CanonicalImporter` so an externally-edited canonical file (one carrying the hidden
            // `<!-- workout.md:canonical -->` block) actually reconstructs its `PlanRecord`/
            // `WorkoutRecord`, instead of leaving the store permanently divergent from what's synced.
            // A hand-edited file with no canonical block is a no-op here (counted, not erred on) —
            // the coach's review note above is still the right (and only) response to that case.
            self?.ingestCanonicalChanges(changes.map { (path: $0.path, content: $0.content) })
        }
        self.icloud.onExternalChanges = { [weak self] changes in
            self?.onICloudExternalChanges?(changes)
            self?.ingestCanonicalChanges(changes.map { (path: $0.path, content: $0.content) })
        }
    }

    // MARK: - Canonical ingest (domain-primitives.md §11)

    /// Opens a fresh `ModelContext` against the app's single shared `ModelContainer` (see
    /// `WorkoutMDApp.sharedModelContainer`) and runs `CanonicalImporter` over `files`. Safe to call
    /// with an empty array (no-ops) or with files that carry no canonical block (`CanonicalImporter`
    /// counts and skips those rather than erroring). This is the ONGOING ingest path, fed by each
    /// `pull()`'s diff of what changed since last sync — see `restoreFromSync(context:)` below for
    /// the separate FULL-listing path a fresh install/second device needs.
    private func ingestCanonicalChanges(_ files: [(path: String, content: String)]) {
        guard !files.isEmpty else { return }
        let context = ModelContext(WorkoutMDApp.sharedModelContainer)
        _ = CanonicalImporter(context: context).restoreFromSync(files: files)
    }

    /// Full reconstruction for a fresh install / second device (domain-primitives.md §11): fetches
    /// EVERY canonical Markdown file from every enabled sync source — not just what changed since
    /// last sync, which is what `pull()`'s diff-based `onExternalChanges` above ingests — and routes
    /// all of it through `CanonicalImporter`. Every import is itself idempotent (plans upsert-by-id
    /// as a new revision; sessions are append-only skip-if-exists — see `CanonicalImporter`), so
    /// calling this more than once (e.g. the Settings "Restore from sync" action, retried) is safe.
    /// The caller supplies `context` (typically `\.modelContext` from the SwiftUI environment) rather
    /// than this reaching for `WorkoutMDApp.sharedModelContainer` itself, so a caller that already has
    /// a context in scope (like a Settings view) reconciles into the exact same context instance the
    /// UI is observing.
    @discardableResult
    func restoreFromSync(context: ModelContext) async -> CanonicalImporter.RestoreSummary {
        var files: [(path: String, content: String)] = []

        if AppSettings.shared.icloudSyncEnabled, let icloudFiles = try? await icloud.fetchAllMarkdownFiles() {
            files.append(contentsOf: icloudFiles)
        }
        if isAuthenticated, let githubFiles = try? await sync.fetchAllMarkdownFiles() {
            files.append(contentsOf: githubFiles)
        }

        return CanonicalImporter(context: context).restoreFromSync(files: files)
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

    // MARK: - Plan commit (plan.md carries the active PlanSnapshot + canonical block)

    /// Renders `snapshot` (typically `PlanRepository.activeSnapshot()`) via the snapshot-aware
    /// `MarkdownGenerator.renderPlan(_:)` — human body plus the hidden canonical block
    /// (domain-primitives.md §11) — and writes it to every enabled sync target as `plan.md`, mirroring
    /// `commitSession`'s shape (independent iCloud/GitHub writes, GitHub failures queue for retry).
    /// Called wherever a plan is actually written (`AppCoachHost.planApply`, today) rather than on a
    /// timer, so `plan.md` is never more than one coach turn stale.
    @discardableResult
    func commitPlan(_ snapshot: PlanSnapshot) async -> Bool {
        let markdown = MarkdownGenerator.renderPlan(snapshot)

        if AppSettings.shared.icloudSyncEnabled {
            _ = try? await icloud.writePlan(markdown: markdown)
        }

        guard isAuthenticated else { return false }
        do {
            _ = try await sync.commitSession(markdown: markdown, path: "plan.md", message: "Update plan.md")
            return true
        } catch {
            sync.enqueueRetry(markdown: markdown, path: "plan.md", message: "Update plan.md")
            return false
        }
    }

    private func commitSessionToICloud(_ record: WorkoutRecord, markdown: String) async {
        guard AppSettings.shared.icloudSyncEnabled else { return }
        icloudStatus = .syncing
        do {
            let filename = GitHubSync.sessionFileName(for: record)
            _ = try await icloud.writeSession(markdown: markdown, filename: filename)
            // Plan mirroring is handled where a ModelContext/active PlanRecord is available
            // (plan export is also available via the editor's ShareLink). Session markdown is the
            // primary synced artifact here.
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
