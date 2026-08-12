import Foundation
import SwiftData

// MARK: - PlanRecord <-> PlanSnapshot bridge
//
// See `docs/architecture/domain-primitives.md` §4. `PlanSnapshot` (Canonical/PlanSnapshot.swift) is
// the single canonical value form; `PlanRecord` (PlanModels.swift) is the persisted SwiftData graph.
// `toSnapshot()` reads the graph into a value; `PlanReconciler.reconcile` writes a value back into
// the graph as an upsert-by-UUID diff, preserving object identity for matched records so `@Query`
// views animate rather than flash-reload.

extension PlanRecord {
    /// Builds the canonical value-layer snapshot of this plan. Sessions come from `orderedSessions`
    /// (each session's blocks via `blocks(in:)`); if this plan predates `PlanMigrator.backfill` (no
    /// sessions yet, blocks still carry `sessionID == nil`), a single session is synthesized here so
    /// every caller always sees `sessions.count >= 1` — this is a read-time fallback only, it does
    /// NOT itself persist the synthesized session (that's `PlanMigrator`'s job).
    func toSnapshot() -> PlanSnapshot {
        var sessions = orderedSessions.map { session in
            SessionSnapshot(
                id: session.id,
                name: session.name,
                blocks: blocks(in: session).map { $0.toBlockSnapshot() }
            )
        }
        if sessions.isEmpty {
            let legacyBlocks = blocks.filter { $0.sessionID == nil }.sorted { $0.order < $1.order }
            if !legacyBlocks.isEmpty {
                sessions = [
                    SessionSnapshot(
                        id: UUID(), name: "Workout", blocks: legacyBlocks.map { $0.toBlockSnapshot() })
                ]
            }
        }
        return PlanSnapshot(
            id: id,
            name: name,
            goal: goal,
            notes: notes,
            sessions: sessions,
            cursorSessionID: nextSessionID ?? sessions.first?.id
        )
    }
}

private extension PlanBlockRecord {
    func toBlockSnapshot() -> BlockSnapshot {
        BlockSnapshot(
            id: id,
            kind: kind.toSnapshotKind(),
            label: label,
            rounds: rounds,
            restSeconds: restSeconds,
            exercises: orderedExercises.map { $0.toExerciseSnapshot() }
        )
    }
}

private extension PlanExerciseRecord {
    func toExerciseSnapshot() -> ExerciseSnapshot {
        ExerciseSnapshot(id: id, name: name, cue: cue, sets: orderedSets.map { $0.toSetSnapshot() })
    }
}

private extension PlanSetRecord {
    func toSetSnapshot() -> SetSnapshot {
        SetSnapshot(
            id: id, reps: reps, weight: weight, seconds: seconds,
            targetMinKg: targetMinKg, targetMaxKg: targetMaxKg)
    }
}

private extension PlanBlockKind {
    func toSnapshotKind() -> BlockKindSnapshot {
        switch self {
        case .straight: return .straight
        case .superset: return .superset
        case .circuit: return .circuit
        }
    }
}

private extension BlockKindSnapshot {
    func toRecordKind() -> PlanBlockKind {
        switch self {
        case .straight: return .straight
        case .superset: return .superset
        case .circuit: return .circuit
        }
    }
}

// MARK: - Reconciler

/// Upsert-by-UUID diff from a `PlanSnapshot` into a `PlanRecord`'s SwiftData graph (see
/// domain-primitives.md §4): every level (sessions, blocks, exercises, sets) matches existing records
/// by id, updates them in place (preserving object identity so `@Query` animates), inserts records
/// for new ids, and deletes records whose id is no longer present. `order` is (re)assigned from each
/// level's array index in the snapshot. Blocks keep their existing `plan` relationship (see the
/// migration-safety note on `PlanSessionRecord`) and are additionally stamped with the `sessionID` of
/// the session that now contains them.
enum PlanReconciler {
    static func reconcile(_ snapshot: PlanSnapshot, into plan: PlanRecord, context: ModelContext) {
        plan.name = snapshot.name
        plan.goal = snapshot.goal
        plan.notes = snapshot.notes

        reconcileSessions(snapshot.sessions, into: plan, context: context)
        reconcileBlocks(snapshot.sessions, into: plan, context: context)

        plan.nextSessionID = snapshot.cursorSessionID
    }

    // MARK: Sessions

    private static func reconcileSessions(
        _ sessionSnapshots: [SessionSnapshot], into plan: PlanRecord, context: ModelContext
    ) {
        var existingByID = Dictionary(uniqueKeysWithValues: plan.sessions.map { ($0.id, $0) })
        var keptIDs = Set<UUID>()

        for (index, snap) in sessionSnapshots.enumerated() {
            keptIDs.insert(snap.id)
            if let record = existingByID[snap.id] {
                record.order = index
                record.name = snap.name
            } else {
                let record = PlanSessionRecord(id: snap.id, order: index, name: snap.name)
                context.insert(record)
                record.plan = plan
                plan.sessions.append(record)
            }
        }

        for (id, stale) in existingByID where !keptIDs.contains(id) {
            if let idx = plan.sessions.firstIndex(where: { $0.id == id }) {
                plan.sessions.remove(at: idx)
            }
            context.delete(stale)
        }
    }

    // MARK: Blocks (flat under `plan.blocks`, grouped by `sessionID`)

    private static func reconcileBlocks(
        _ sessionSnapshots: [SessionSnapshot], into plan: PlanRecord, context: ModelContext
    ) {
        var existingByID = Dictionary(uniqueKeysWithValues: plan.blocks.map { ($0.id, $0) })
        var keptIDs = Set<UUID>()

        for session in sessionSnapshots {
            for (index, blockSnap) in session.blocks.enumerated() {
                keptIDs.insert(blockSnap.id)
                let record: PlanBlockRecord
                if let existing = existingByID[blockSnap.id] {
                    record = existing
                } else {
                    record = PlanBlockRecord(
                        id: blockSnap.id, order: index, kind: blockSnap.kind.toRecordKind(),
                        label: blockSnap.label, rounds: blockSnap.rounds,
                        restSeconds: blockSnap.restSeconds, sessionID: session.id)
                    context.insert(record)
                    record.plan = plan
                    plan.blocks.append(record)
                }
                record.order = index
                record.kind = blockSnap.kind.toRecordKind()
                record.label = blockSnap.label
                record.rounds = blockSnap.rounds
                record.restSeconds = blockSnap.restSeconds
                record.sessionID = session.id

                reconcileExercises(blockSnap.exercises, into: record, context: context)
            }
        }

        for (id, stale) in existingByID where !keptIDs.contains(id) {
            if let idx = plan.blocks.firstIndex(where: { $0.id == id }) {
                plan.blocks.remove(at: idx)
            }
            context.delete(stale)
        }
    }

    // MARK: Exercises

    private static func reconcileExercises(
        _ exerciseSnapshots: [ExerciseSnapshot], into block: PlanBlockRecord, context: ModelContext
    ) {
        var existingByID = Dictionary(uniqueKeysWithValues: block.exercises.map { ($0.id, $0) })
        var keptIDs = Set<UUID>()

        for (index, snap) in exerciseSnapshots.enumerated() {
            keptIDs.insert(snap.id)
            let record: PlanExerciseRecord
            if let existing = existingByID[snap.id] {
                record = existing
            } else {
                record = PlanExerciseRecord(id: snap.id, order: index, name: snap.name, cue: snap.cue)
                context.insert(record)
                record.block = block
                block.exercises.append(record)
            }
            record.order = index
            record.name = snap.name
            record.cue = snap.cue

            reconcileSets(snap.sets, into: record, context: context)
        }

        for (id, stale) in existingByID where !keptIDs.contains(id) {
            if let idx = block.exercises.firstIndex(where: { $0.id == id }) {
                block.exercises.remove(at: idx)
            }
            context.delete(stale)
        }
    }

    // MARK: Sets

    private static func reconcileSets(
        _ setSnapshots: [SetSnapshot], into exercise: PlanExerciseRecord, context: ModelContext
    ) {
        var existingByID = Dictionary(uniqueKeysWithValues: exercise.sets.map { ($0.id, $0) })
        var keptIDs = Set<UUID>()

        for (index, snap) in setSnapshots.enumerated() {
            keptIDs.insert(snap.id)
            let record: PlanSetRecord
            if let existing = existingByID[snap.id] {
                record = existing
            } else {
                record = PlanSetRecord(
                    id: snap.id, order: index, reps: snap.reps, weight: snap.weight,
                    seconds: snap.seconds, targetMinKg: snap.targetMinKg, targetMaxKg: snap.targetMaxKg)
                context.insert(record)
                record.exercise = exercise
                exercise.sets.append(record)
            }
            record.order = index
            record.reps = snap.reps
            record.weight = snap.weight
            record.seconds = snap.seconds
            record.targetMinKg = snap.targetMinKg
            record.targetMaxKg = snap.targetMaxKg
        }

        for (id, stale) in existingByID where !keptIDs.contains(id) {
            if let idx = exercise.sets.firstIndex(where: { $0.id == id }) {
                exercise.sets.remove(at: idx)
            }
            context.delete(stale)
        }
    }
}
