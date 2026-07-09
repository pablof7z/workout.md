import Foundation
import CryptoKit

/// Mirrors the app's Markdown session history into the iCloud ubiquity container (iCloud Documents)
/// at `Documents/{README.md, plan.md, sessions/YYYY-MM-DD-<slug>.md}` — the exact same path/filename
/// convention `GitHubSync` uses under its repo root (see `GitHubSync.sessionFileName(for:)`), so a
/// session written by this app looks identical whether you're browsing it in Files.app or on
/// github.com.
///
/// This is a fully independent mirror: it shares nothing at runtime with `GitHubSync` beyond that
/// filename convention and the rendered Markdown string itself. Enabling/disabling one never touches
/// the other, and a failure in one never blocks the other (see `SyncManager`).
///
/// ## Availability
/// `FileManager.url(forUbiquityContainerIdentifier:)` returns `nil` when the user isn't signed into
/// iCloud, iCloud Drive is off, or (in a simulator without an iCloud account) the container simply
/// isn't provisioned. `isAvailable` surfaces that as a plain `Bool` so Settings can show "sign in to
/// iCloud" instead of the app silently no-op'ing or crashing. That lookup can be slow on its first
/// call, so it's never performed synchronously on the calling thread — `isAvailable` reads a cached
/// value refreshed by `resolvedContainerURL()` (kicked off once at `init` and again on every
/// `writeSession`/`pull`), rather than blocking a SwiftUI view body.
///
/// ## Coordinated I/O
/// Every read and write goes through `NSFileCoordinator` so it interleaves safely with iCloud's own
/// upload/download daemon and with a presenter on another device editing the same file.
///
/// ## Detecting external changes
/// There's no server-side commit history to diff against (unlike `GitHubSync.pull()`), so this keeps
/// a small local index — `relative path -> SHA-256 hex` — persisted in `UserDefaults`, and:
///   - on the very first `pull()` ever (no persisted index yet), just records the current contents as
///     a baseline without reporting anything as "external" (mirrors `GitHubSync.pull()`'s own
///     first-run behavior);
///   - on every subsequent `pull()`, diffs each `.md` file's current hash against its last-known hash,
///     skips anything this instance just wrote itself this run (tracked in `recentlyWritten`), and
///     reports the rest via `onExternalChanges`.
/// `startObserving()`/`stopObserving()` wrap an `NSMetadataQuery` scoped to
/// `NSMetadataQueryUbiquitousDocumentsScope` so a change made on another device while this app is in
/// the foreground triggers a `pull()` promptly instead of waiting for the next explicit call.
final class ICloudSync {
    struct ChangedFile: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let content: String
        let modifiedAt: Date
    }

    enum ICloudSyncError: Error, LocalizedError {
        case unavailable
        case coordinationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "iCloud is not available — sign in to iCloud (Settings app > your name > iCloud) and make sure iCloud Drive is on."
            case .coordinationFailed(let message):
                return "iCloud file coordination failed: \(message)"
            }
        }
    }

    /// The ubiquity container declared in `WorkoutMD.entitlements`
    /// (`com.apple.developer.icloud-container-identifiers` /
    /// `com.apple.developer.ubiquity-container-identifiers`).
    static let containerIdentifier = "iCloud.com.workoutmd.prototype"

    /// Fired with any file this instance's `pull()` finds changed by something other than itself —
    /// i.e. an edit made on another device (or directly in Files.app) syncing in. Wiring an actual
    /// coach-review flow for these is a later workstream, same as `GitHubSync.onExternalChanges`.
    var onExternalChanges: (([ChangedFile]) -> Void)?

    private let fileManager: FileManager
    private let defaults: UserDefaults

    /// Cached result of the last `resolvedContainerURL()` call — read synchronously by `isAvailable`
    /// so Settings can display a status without blocking on the (occasionally slow) ubiquity lookup.
    private(set) var containerURL: URL?

    /// Content hashes this instance itself just wrote (`relative path -> sha256 hex`), so the next
    /// `pull()` can tell "iCloud propagated my own write back to me" apart from a genuine external
    /// edit. Entries are consumed (removed) the first time `pull()` matches them.
    private var recentlyWritten: [String: String] = [:]

    private var metadataQuery: NSMetadataQuery?
    private var gatheringObserver: NSObjectProtocol?
    private var updateObserver: NSObjectProtocol?

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
        // Kick off an initial availability check in the background so `isAvailable` isn't
        // permanently "false" for an app session that never happens to call `pull()`/`writeSession`.
        Task { [weak self] in _ = await self?.resolvedContainerURL() }
    }

    /// Whether the ubiquity container looked reachable as of the last check (init, or the most
    /// recent `writeSession`/`pull`). Synchronous and cheap — never performs the underlying
    /// `FileManager` lookup itself, so it's safe to read from a view body.
    var isAvailable: Bool { containerURL != nil }

    // MARK: - Ubiquity container paths

    /// Performs the (occasionally slow) ubiquity container lookup off the calling thread and caches
    /// the result in `containerURL`. Safe to call often — `FileManager` itself caches the expensive
    /// part after the first real lookup.
    @discardableResult
    private func resolvedContainerURL() async -> URL? {
        let identifier = Self.containerIdentifier
        let url = await Task.detached(priority: .utility) { [fileManager] in
            fileManager.url(forUbiquityContainerIdentifier: identifier)
                ?? fileManager.url(forUbiquityContainerIdentifier: nil)
        }.value
        containerURL = url
        return url
    }

    private func resolvedDocumentsURL() async -> URL? {
        guard let containerURL = await resolvedContainerURL() else { return nil }
        return containerURL.appendingPathComponent("Documents", isDirectory: true)
    }

    private func resolvedSessionsURL() async -> URL? {
        guard let documentsURL = await resolvedDocumentsURL() else { return nil }
        return documentsURL.appendingPathComponent("sessions", isDirectory: true)
    }

    // MARK: - Writing a session

    /// Writes `markdown` to `Documents/sessions/{filename}`, creating intermediate directories as
    /// needed, and best-effort updates the `README.md` index (a failure there doesn't fail the
    /// session write itself — mirrors `GitHubSync.commitSession`). Idempotent: if the file already
    /// holds identical content, this is a no-op (returns `false`) rather than touching the file (and
    /// re-triggering an upload) for nothing.
    @discardableResult
    func writeSession(markdown: String, filename: String) async throws -> Bool {
        guard let sessionsURL = await resolvedSessionsURL() else {
            throw ICloudSyncError.unavailable
        }
        try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)
        let fileURL = sessionsURL.appendingPathComponent(filename)
        let relativePath = "sessions/\(filename)"

        let wrote = try coordinatedWriteIfChanged(markdown, to: fileURL)
        if wrote {
            let hash = Self.sha256Hex(markdown)
            recentlyWritten[relativePath] = hash
            persistedHashes[relativePath] = hash
            try? await updateReadmeIndex(newFilename: filename)
        }
        return wrote
    }

    /// Writes the current workout plan to `Documents/plan.md` — the plan-side counterpart to the
    /// per-session files, so the ubiquity container carries both what was planned and what happened.
    /// Idempotent the same way `writeSession` is.
    @discardableResult
    func writePlan(markdown: String) async throws -> Bool {
        guard let documentsURL = await resolvedDocumentsURL() else {
            throw ICloudSyncError.unavailable
        }
        try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        let planURL = documentsURL.appendingPathComponent("plan.md")
        let wrote = try coordinatedWriteIfChanged(markdown, to: planURL)
        if wrote {
            let hash = Self.sha256Hex(markdown)
            recentlyWritten["plan.md"] = hash
            persistedHashes["plan.md"] = hash
        }
        return wrote
    }

    // MARK: - README index

    private static let defaultReadme = """
    # Workout.md (iCloud)

    This folder is kept in sync by the Workout.md app via iCloud Drive/Documents. `plan.md` is the \
    current workout plan; each file under `sessions/` is a Markdown snapshot of one workday's \
    session. Feel free to edit these directly (Files.app, or on any other device signed into the \
    same iCloud account) — the app treats anything it didn't just write itself as an external \
    change for the in-app coach to review.

    ## Sessions
    """

    private func updateReadmeIndex(newFilename: String) async throws {
        guard let documentsURL = await resolvedDocumentsURL() else { return }
        let readmeURL = documentsURL.appendingPathComponent("README.md")
        let existing = try? coordinatedRead(at: readmeURL)
        var lines = (existing ?? Self.defaultReadme).components(separatedBy: "\n")
        let bullet = "- [sessions/\(newFilename)](sessions/\(newFilename))"
        guard !lines.contains(bullet) else { return }
        lines.append(bullet)
        let updated = lines.joined(separator: "\n")
        guard try coordinatedWriteIfChanged(updated, to: readmeURL) else { return }
        let hash = Self.sha256Hex(updated)
        recentlyWritten["README.md"] = hash
        persistedHashes["README.md"] = hash
    }

    // MARK: - Pull / ingest external changes

    /// Enumerates every `.md` file under the ubiquity container's `Documents` directory, diffs each
    /// against its last-known content hash, and returns/reports (via `onExternalChanges`) anything
    /// that changed and wasn't this instance's own recent write. See the type doc comment for the
    /// first-run baseline behavior. Safe to call opportunistically (foreground, `NSMetadataQuery`
    /// callback, a manual "Sync now" button) — every step is idempotent.
    @discardableResult
    func pull() async throws -> [ChangedFile] {
        guard let documentsURL = await resolvedDocumentsURL() else {
            throw ICloudSyncError.unavailable
        }
        try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)

        let fileURLs = try coordinatedContentsOfDirectory(at: documentsURL)
            .filter { $0.pathExtension == "md" }

        let isFirstRun = !hasEstablishedBaseline
        var updatedHashes = persistedHashes
        var changed: [ChangedFile] = []

        for url in fileURLs {
            // Best-effort: ask iCloud to materialize the latest version before we read it. Not
            // awaited — a file that's mid-download still reads (its last-downloaded bytes); the next
            // pull picks up the rest once it finishes.
            try? fileManager.startDownloadingUbiquitousItem(at: url)
            guard let content = try? coordinatedRead(at: url) else { continue }

            let relativePath = relativePath(for: url, in: documentsURL)
            let hash = Self.sha256Hex(content)
            let previousHash = persistedHashes[relativePath]
            updatedHashes[relativePath] = hash

            guard !isFirstRun else { continue } // establishing baseline only this run
            guard hash != previousHash else { continue }
            if recentlyWritten[relativePath] == hash {
                recentlyWritten.removeValue(forKey: relativePath) // our own write, propagated back
                continue
            }

            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let modifiedAt = (attributes?[.modificationDate] as? Date) ?? .now
            changed.append(ChangedFile(path: relativePath, content: content, modifiedAt: modifiedAt))
        }

        persistedHashes = updatedHashes
        hasEstablishedBaseline = true

        if !changed.isEmpty {
            onExternalChanges?(changed)
        }
        return changed
    }

    // MARK: - Live observation (NSMetadataQuery)

    /// Starts watching the ubiquity container for changes made elsewhere (another device, or an edit
    /// in Files.app) while the app is in the foreground, triggering a `pull()` shortly after anything
    /// changes. Call from `SyncManager.appDidBecomeActive`. No-ops if already observing or iCloud
    /// isn't available yet (in which case there's nothing to watch).
    func startObserving() {
        guard metadataQuery == nil else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*.md")
        query.notificationBatchingInterval = 1.0

        gatheringObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self] _ in self?.handleQueryUpdate() }
        updateObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] _ in self?.handleQueryUpdate() }

        metadataQuery = query
        query.start()
    }

    /// Stops the live watch. Call from `SyncManager.appDidEnterBackground` — an `NSMetadataQuery` left
    /// running while suspended just burns battery for updates nothing can react to.
    func stopObserving() {
        if let gatheringObserver { NotificationCenter.default.removeObserver(gatheringObserver) }
        if let updateObserver { NotificationCenter.default.removeObserver(updateObserver) }
        gatheringObserver = nil
        updateObserver = nil
        metadataQuery?.stop()
        metadataQuery = nil
    }

    private func handleQueryUpdate() {
        Task { [weak self] in _ = try? await self?.pull() }
    }

    // MARK: - Coordinated file I/O

    private func coordinatedContentsOfDirectory(at url: URL) throws -> [URL] {
        var results: [URL] = []
        var coordinatorError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            guard let enumerator = fileManager.enumerator(
                at: coordinatedURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for case let fileURL as URL in enumerator {
                results.append(fileURL)
            }
        }
        if let coordinatorError { throw coordinatorError }
        return results
    }

    private func coordinatedRead(at url: URL) throws -> String {
        var content: String?
        var coordinatorError: NSError?
        var readError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            do {
                content = try String(contentsOf: coordinatedURL, encoding: .utf8)
            } catch {
                readError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let readError { throw readError }
        guard let content else { throw ICloudSyncError.coordinationFailed("no content read") }
        return content
    }

    /// Coordinated write that first reads the existing content under the same write lock and skips
    /// the actual write if it's already identical — the iCloud-file analog of `GitHubSync`'s
    /// `.unchanged` short-circuit, so a re-save of an unmodified session doesn't force a needless
    /// re-upload.
    @discardableResult
    private func coordinatedWriteIfChanged(_ content: String, to url: URL) throws -> Bool {
        var coordinatorError: NSError?
        var writeError: Error?
        var didWrite = false
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            let existing = try? String(contentsOf: coordinatedURL, encoding: .utf8)
            guard existing != content else { return }
            do {
                try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                didWrite = true
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
        return didWrite
    }

    private func relativePath(for url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        var path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath) {
            path.removeFirst(rootPath.count)
        }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Local change-detection index (UserDefaults)

    private var hashesKey: String { "com.workoutmd.sync.icloud.lastKnownHashes" }
    private var baselineKey: String { "com.workoutmd.sync.icloud.baselineEstablished" }

    private var persistedHashes: [String: String] {
        get {
            guard let data = defaults.data(forKey: hashesKey),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: hashesKey)
        }
    }

    private var hasEstablishedBaseline: Bool {
        get { defaults.bool(forKey: baselineKey) }
        set { defaults.set(newValue, forKey: baselineKey) }
    }

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
