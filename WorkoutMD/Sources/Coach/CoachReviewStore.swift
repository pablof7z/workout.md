import Foundation
import Observation

/// One terse coach note produced by reviewing an external (non-app) Markdown change pulled from
/// GitHub sync — the "agent reviews new commits" half of the sync promise (M2). `GitHubSync.pull()`
/// already ingests the changed content and calls `SyncManager.onExternalChanges`; this is what that
/// hook actually produces once `CoachController.reviewExternalChanges(_:)` wires it to a real turn.
struct CoachReviewNote: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    /// The `sessions/*.md`/`README.md` paths that changed in the reviewed commit(s).
    let changedPaths: [String]
    let commitMessage: String
    /// The coach's own one-line review, in its normal dry voice — e.g. "saw you added drop sets to
    /// Tuesday's session, I'll bias volume up on that block."
    let note: String

    init(id: UUID = UUID(), date: Date = .now, changedPaths: [String], commitMessage: String, note: String) {
        self.id = id
        self.date = date
        self.changedPaths = changedPaths
        self.commitMessage = commitMessage
        self.note = note
    }
}

/// Durable, file-backed inbox of coach review notes — the lightweight "coach reviewed your changes"
/// surface the product spec calls for, plus the feed that folds prior reviews into subsequent
/// grounding. Persisted independently of SwiftData (JSON in Application Support, mirroring
/// `GitHubSync`'s own pending-commit queue file) so `SyncManager`'s singleton — which has no
/// `ModelContext`, not being a SwiftUI-environment-scoped object — can produce and store these
/// without needing one threaded in.
@Observable
final class CoachReviewStore {
    static let shared = CoachReviewStore()

    private(set) var notes: [CoachReviewNote] = []
    /// Whether anything here hasn't been surfaced to the user yet — mirrors
    /// `FabricController.hasUnseenMessages` so a future badge/inbox UI has something to bind to.
    private(set) var hasUnseen = false

    private static let limit = 30
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    private static func defaultFileURL() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkoutMD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("coach-review-notes.json")
    }

    func append(_ note: CoachReviewNote) {
        notes.append(note)
        if notes.count > Self.limit {
            notes.removeFirst(notes.count - Self.limit)
        }
        hasUnseen = true
        save()
    }

    func markSeen() { hasUnseen = false }

    /// Folded into the coach's grounding context for subsequent turns (see `CoachController.send`) —
    /// this is the "feed it into subsequent grounding" half of M2, so a review the coach did while the
    /// user wasn't even looking still informs the very next reply.
    func contextSnippet(limit: Int = 3) -> String {
        guard !notes.isEmpty else { return "" }
        let recent = notes.suffix(limit)
        var lines = ["Recent reviews of external changes (Markdown edited outside the app, then synced in):"]
        lines.append(contentsOf: recent.map { "- \($0.note)" })
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        notes = (try? JSONDecoder().decode([CoachReviewNote].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
