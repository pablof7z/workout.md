import Foundation
import SwiftData

// MARK: - PlanRepository
//
// See `docs/architecture/domain-primitives.md` §3/§4. The single write/read gateway between the
// canonical value layer (`PlanSnapshot`/`PlanMutation`/`PlanEngine`) and the persisted SwiftData
// graph (`PlanRecord`/`PlanSessionRecord`/.../`PlanRevisionRecord`). Every plan-changing outcome —
// create, coach edit, propose-then-confirm, restore — funnels through `apply`/`createPlan`/
// `restore`, so there is exactly one reconcile/revision code path, not one per call site.
//
// Mirrors `PlanStore`'s style: a lightweight namespace-ish type over an explicit `ModelContext` the
// caller already has in scope (a SwiftUI `@Environment` or a background task's own context), not a
// singleton or an `@Observable` service.
struct PlanRepository {
    let context: ModelContext

    private static let encoder: JSONEncoder = JSONEncoder()
    private static let decoder: JSONDecoder = JSONDecoder()

    enum PlanApplyMode: Equatable {
        /// Reconcile the SwiftData graph to the new snapshot, write a `PlanRevisionRecord`, save.
        case apply
        /// Return the candidate snapshot only — do NOT reconcile or persist anything. The UI (or the
        /// coach) previews it and either re-applies in `.apply` or discards.
        case propose
    }

    struct PlanApplyResult {
        let snapshot: PlanSnapshot
        /// The `PlanRevisionRecord.id` written for this change; `nil` for `.propose` (nothing was
        /// persisted, so there's nothing to reference).
        let revisionID: UUID?
        let proposed: Bool
    }

    enum PlanRepositoryError: Error, Equatable {
        case planNotFound(UUID)
        case revisionNotFound(UUID)
    }

    // MARK: - Reads

    func snapshot(of planID: UUID) -> PlanSnapshot? {
        fetchPlan(id: planID)?.toSnapshot()
    }

    func activeSnapshot() -> PlanSnapshot? {
        var descriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.isActive == true })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.toSnapshot()
    }

    /// Newest first.
    func revisions(of planID: UUID) -> [PlanRevisionRecord] {
        let descriptor = FetchDescriptor<PlanRevisionRecord>(
            predicate: #Predicate { $0.planID == planID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Apply / propose

    /// Applies `mutation` to `planID`'s current snapshot via the pure `PlanEngine` (atomic — if any
    /// op fails, nothing here runs). In `.apply` mode the resulting snapshot is reconciled into the
    /// `PlanRecord` graph and a `PlanRevisionRecord` is written; in `.propose` mode the candidate
    /// snapshot is returned without touching the stored graph at all.
    @discardableResult
    func apply(
        _ mutation: PlanMutation, to planID: UUID, mode: PlanApplyMode = .apply
    ) throws -> PlanApplyResult {
        guard let plan = fetchPlan(id: planID) else { throw PlanRepositoryError.planNotFound(planID) }
        let current = plan.toSnapshot()
        let candidate = try PlanEngine.apply(mutation, to: current)

        guard mode == .apply else {
            return PlanApplyResult(snapshot: candidate, revisionID: nil, proposed: true)
        }

        PlanReconciler.reconcile(candidate, into: plan, context: context)
        let revision = try writeRevision(
            planID: planID, snapshot: candidate,
            summary: mutation.summary ?? PlanEngine.summarize(mutation), mutation: mutation
        )
        try context.save()
        return PlanApplyResult(snapshot: candidate, revisionID: revision.id, proposed: false)
    }

    // MARK: - Create

    /// Persists a proposal the athlete has explicitly accepted. Until this method runs the
    /// `PlanSnapshot` is only in-memory UI state and cannot change the current plan.
    @discardableResult
    func acceptProposal(_ snapshot: PlanSnapshot, activate: Bool = true) throws -> PlanRecord {
        let accepted = snapshotWithFreshIdentity(snapshot)
        let plan = PlanRecord(
            id: accepted.id, name: accepted.name, goal: accepted.goal,
            notes: accepted.notes, isActive: false, nextSessionID: accepted.cursorSessionID
        )
        context.insert(plan)
        PlanReconciler.reconcile(accepted, into: plan, context: context)
        try writeRevision(
            planID: plan.id, snapshot: accepted,
            summary: "Accepted coach proposal", mutation: nil
        )
        if activate {
            PlanStore.setActive(plan, context: context)
        } else {
            try context.save()
        }
        return plan
    }

    /// Starts from `PlanEngine.empty`, applies `mutation` (the ordinary way to build up a brand-new
    /// plan's sessions/blocks/exercises/sets — see domain-primitives.md §2/§3), materializes a new
    /// `PlanRecord`, reconciles it, inserts it, and writes a baseline revision. Optionally activates
    /// it (via `PlanStore.setActive`, reused rather than duplicated here).
    @discardableResult
    func createPlan(_ mutation: PlanMutation, name: String, activate: Bool) throws -> PlanRecord {
        let empty = PlanEngine.empty(name: name)
        let snapshot = try PlanEngine.apply(mutation, to: empty)

        let plan = PlanRecord(id: snapshot.id, name: snapshot.name, goal: snapshot.goal, notes: snapshot.notes)
        context.insert(plan)
        PlanReconciler.reconcile(snapshot, into: plan, context: context)
        try writeRevision(
            planID: plan.id, snapshot: snapshot,
            summary: mutation.summary ?? PlanEngine.summarize(mutation), mutation: mutation
        )

        if activate {
            PlanStore.setActive(plan, context: context)
        } else {
            try context.save()
        }
        return plan
    }

    // MARK: - Restore

    /// Restore is itself a normal versioned change (domain-primitives.md §4), not a special code
    /// path: decode the target revision's stored `snapshotJSON` and reconcile the plan DIRECTLY to
    /// it — the simplest correct approach, since the destination snapshot is already fully known, so
    /// there's no need to compute a diff-as-`PlanMutation` the way `apply` does — then write a NEW
    /// revision recording the restore (`mutationJSON` is left `nil`: "restore to revision X" isn't
    /// itself expressible as a `PlanMutation` batch).
    @discardableResult
    func restore(revisionID: UUID) throws -> PlanApplyResult {
        var descriptor = FetchDescriptor<PlanRevisionRecord>(predicate: #Predicate { $0.id == revisionID })
        descriptor.fetchLimit = 1
        guard let revision = try context.fetch(descriptor).first else {
            throw PlanRepositoryError.revisionNotFound(revisionID)
        }
        guard let plan = fetchPlan(id: revision.planID) else {
            throw PlanRepositoryError.planNotFound(revision.planID)
        }
        let snapshot = try Self.decoder.decode(PlanSnapshot.self, from: Data(revision.snapshotJSON.utf8))

        PlanReconciler.reconcile(snapshot, into: plan, context: context)
        let newRevision = try writeRevision(
            planID: plan.id, snapshot: snapshot, summary: "Restored: \(revision.summary)", mutation: nil
        )
        try context.save()
        return PlanApplyResult(snapshot: snapshot, revisionID: newRevision.id, proposed: false)
    }

    // MARK: - Private

    private func fetchPlan(id: UUID) -> PlanRecord? {
        var descriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// A proposal may have been derived from an existing plan and therefore carry persisted IDs.
    /// Accepting it creates a distinct plan, so every identity in the graph is reminted together.
    private func snapshotWithFreshIdentity(_ snapshot: PlanSnapshot) -> PlanSnapshot {
        let sessions = snapshot.sessions.map { session in
            SessionSnapshot(
                id: UUID(), name: session.name,
                blocks: session.blocks.map { block in
                    BlockSnapshot(
                        id: UUID(), kind: block.kind, label: block.label,
                        rounds: block.rounds, restSeconds: block.restSeconds,
                        exercises: block.exercises.map { exercise in
                            ExerciseSnapshot(
                                id: UUID(), name: exercise.name, cue: exercise.cue,
                                sets: exercise.sets.map { set in
                                    SetSnapshot(
                                        id: UUID(), reps: set.reps, weight: set.weight,
                                        seconds: set.seconds, targetMinKg: set.targetMinKg,
                                        targetMaxKg: set.targetMaxKg)
                                })
                        })
                })
        }
        return PlanSnapshot(
            id: UUID(), name: snapshot.name, goal: snapshot.goal, notes: snapshot.notes,
            sessions: sessions, cursorSessionID: sessions.first?.id
        )
    }

    @discardableResult
    private func writeRevision(
        planID: UUID, snapshot: PlanSnapshot, summary: String, mutation: PlanMutation?
    ) throws -> PlanRevisionRecord {
        let snapshotData = try Self.encoder.encode(snapshot)
        let mutationJSON: String?
        if let mutation {
            mutationJSON = String(decoding: try Self.encoder.encode(mutation), as: UTF8.self)
        } else {
            mutationJSON = nil
        }
        let revision = PlanRevisionRecord(
            planID: planID,
            summary: summary,
            snapshotJSON: String(decoding: snapshotData, as: UTF8.self),
            mutationJSON: mutationJSON
        )
        context.insert(revision)
        return revision
    }
}
