import Foundation
import SwiftData

/// The write side of the round trip (domain-primitives.md §11): reconstructs SwiftData records from
/// the canonical DTOs `MarkdownParser` decodes out of synced Markdown. This is what makes `pull()`/
/// restore actually rebuild the app's data on a fresh install or second device, instead of just
/// handing the coach something to read while the store stays permanently divergent from what's on
/// GitHub/iCloud.
///
/// ## Conflict policy (domain-primitives.md §11)
/// - **Plans** (`importPlan`) are last-writer-wins: an external change to a plan this device already
///   has lands as a NEW `PlanRevisionRecord` via `PlanReconciler` — never a silent, un-undoable
///   overwrite. `PlanRepository.restore` can always get back to what this device had before the
///   import. A plan id this device has never seen is created (and activated only if it's the only
///   plan on device — never silently stealing "active" from a plan already in progress).
/// - **Completed-workout history** (`importSession`) is FACTUAL and APPEND-ONLY: once a
///   `WorkoutRecord` with a given id exists, its logged facts (actual reps/weight/seconds, rpe,
///   skipped/substituted, notes) are never overwritten by importing the "same" session id again —
///   what actually happened during a workout doesn't retroactively change because a synced file
///   changed. A session id not yet seen is inserted in full.
struct CanonicalImporter {
    let context: ModelContext

    // MARK: - Plans

    enum PlanImportOutcome: Equatable {
        /// No plan with this id existed yet — created (and activated iff it's the only plan).
        case created(UUID)
        /// A plan with this id already existed and its content differed — a new
        /// `PlanRevisionRecord` was written and the plan reconciled to the incoming snapshot.
        case revised(UUID, revisionID: UUID)
        /// A plan with this id already existed and already matched the incoming snapshot exactly —
        /// nothing written.
        case unchanged(UUID)
    }

    @discardableResult
    func importPlan(_ snapshot: PlanSnapshot) -> PlanImportOutcome {
        if let existing = fetchPlan(id: snapshot.id) {
            guard existing.toSnapshot() != snapshot else { return .unchanged(snapshot.id) }
            PlanReconciler.reconcile(snapshot, into: existing, context: context)
            let revision = writeRevision(
                planID: snapshot.id, snapshot: snapshot, summary: "Imported external change")
            try? context.save()
            return .revised(snapshot.id, revisionID: revision.id)
        }

        let plan = PlanRecord(id: snapshot.id, name: snapshot.name, goal: snapshot.goal, notes: snapshot.notes)
        context.insert(plan)
        PlanReconciler.reconcile(snapshot, into: plan, context: context)
        writeRevision(planID: plan.id, snapshot: snapshot, summary: "Restored from sync")

        let existingPlanCount = (try? context.fetchCount(FetchDescriptor<PlanRecord>())) ?? 0
        if existingPlanCount <= 1 {
            PlanStore.setActive(plan, context: context) // also saves
        } else {
            try? context.save()
        }
        return .created(snapshot.id)
    }

    // MARK: - Sessions (completed-workout history)

    enum SessionImportOutcome: Equatable {
        case inserted(UUID)
        /// A `WorkoutRecord` with this id already exists — a no-op, by design. See the type doc
        /// comment: history is factual and append-only, so the already-stored logged facts win.
        case skippedExisting(UUID)
    }

    @discardableResult
    func importSession(_ dto: SessionDTO) -> SessionImportOutcome {
        guard fetchWorkout(id: dto.id) == nil else {
            return .skippedExisting(dto.id)
        }
        let record = dto.makeRecord()
        context.insert(record)
        try? context.save()
        return .inserted(dto.id)
    }

    // MARK: - Restore convenience

    struct RestoreSummary: Equatable {
        var plansImported = 0
        var sessionsImported = 0
        var skippedNoCanonicalBlock = 0
    }

    /// Routes a batch of synced files (relative path + raw Markdown content) through the right
    /// importer by path convention: `README.md` is always ignored (export-only index, never a
    /// restore source — see `CanonicalMarkdown`'s doc comment), `plan.md`/anything starting with
    /// `plan` decodes as a `PlanSnapshot`, `sessions/*.md` decodes as a `SessionDTO`. Anything else
    /// is tried against both parsers before giving up (a sync source with a slightly different path
    /// layout shouldn't silently lose files). A file with no canonical block at all — hand-written
    /// Markdown, or a plain export — is counted in `skippedNoCanonicalBlock` rather than treated as
    /// an error, so a whole restore run never crashes on one unparseable file.
    func restoreFromSync(files: [(path: String, content: String)]) -> RestoreSummary {
        var summary = RestoreSummary()
        for file in files {
            guard file.path != "README.md", !file.path.hasSuffix("/README.md") else { continue }

            if file.path == "plan.md" || file.path.hasPrefix("plan") {
                if let snapshot = MarkdownParser.parsePlan(file.content) {
                    importPlan(snapshot)
                    summary.plansImported += 1
                } else {
                    summary.skippedNoCanonicalBlock += 1
                }
            } else if file.path.hasPrefix("sessions/") {
                if let dto = MarkdownParser.parseSession(file.content) {
                    importSession(dto)
                    summary.sessionsImported += 1
                } else {
                    summary.skippedNoCanonicalBlock += 1
                }
            } else if let snapshot = MarkdownParser.parsePlan(file.content) {
                importPlan(snapshot)
                summary.plansImported += 1
            } else if let dto = MarkdownParser.parseSession(file.content) {
                importSession(dto)
                summary.sessionsImported += 1
            } else {
                summary.skippedNoCanonicalBlock += 1
            }
        }
        return summary
    }

    // MARK: - Private

    private func fetchPlan(id: UUID) -> PlanRecord? {
        var descriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchWorkout(id: UUID) -> WorkoutRecord? {
        var descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    private func writeRevision(planID: UUID, snapshot: PlanSnapshot, summary: String) -> PlanRevisionRecord {
        let snapshotJSON = (try? CanonicalMarkdown.encoder.encode(snapshot))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let revision = PlanRevisionRecord(planID: planID, summary: summary, snapshotJSON: snapshotJSON, mutationJSON: nil)
        context.insert(revision)
        return revision
    }
}
