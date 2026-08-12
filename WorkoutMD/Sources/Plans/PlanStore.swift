import Foundation
import SwiftData

/// CRUD + lifecycle operations over `PlanRecord`, mirroring the shape of `MockHistory`'s
/// `seedIfNeeded` (a namespace of static functions over an explicit `ModelContext`, rather than an
/// `@Observable` service) since every call site already has a `ModelContext` in scope (a SwiftUI
/// `@Environment` or a background task's own context) and there's no other shared state to own.
enum PlanStore {

    /// Makes `plan` the sole active plan, deactivating every other one. Safe to call on a plan
    /// that isn't yet inserted into `context` — inserts it first.
    static func setActive(_ plan: PlanRecord, context: ModelContext) {
        if plan.modelContext == nil {
            context.insert(plan)
        }
        let descriptor = FetchDescriptor<PlanRecord>()
        if let all = try? context.fetch(descriptor) {
            for candidate in all {
                candidate.isActive = (candidate.id == plan.id)
            }
        }
        plan.isActive = true
        try? context.save()
    }

    /// Routed through `PlanRepository.createPlan` (domain-primitives.md §3/§4): a blank plan is just
    /// `PlanEngine.empty` plus a single default session, applied as an ordinary `PlanMutation` — so
    /// even a "New Plan" from scratch gets a baseline `PlanRevisionRecord` the same way every other
    /// plan-creating path does, rather than a one-off insert with no revision history.
    @discardableResult
    static func createBlank(name: String, goal: String?, context: ModelContext) -> PlanRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let planName = trimmedName.isEmpty ? "New Plan" : trimmedName
        let sessionID = UUID()
        let mutation = PlanMutation(operations: [
            .setPlanMeta(name: .keep, goal: goal.map(FieldEdit.set) ?? .keep, notes: .keep),
            .addSession(id: sessionID, name: "Workout", index: nil),
            .setCursor(sessionID: sessionID)
        ])
        return createViaRepository(mutation, name: planName, context: context) {
            let plan = PlanRecord(name: planName, goal: goal)
            attachDefaultSession(to: plan)
            return plan
        }
    }

    /// Deep-copies `plan`'s whole block/exercise/set graph under a new identity (fresh UUIDs
    /// throughout — never the source plan's own ids, per `addBlock`'s "supply the NEW element's own
    /// uuid" contract) — never active by default, so duplicating doesn't silently swap out what
    /// Today runs. Routed through `PlanRepository.createPlan` like `createBlank` above.
    @discardableResult
    static func duplicate(_ plan: PlanRecord, newName: String? = nil, context: ModelContext) -> PlanRecord {
        let name = newName?.isEmpty == false ? newName! : "\(plan.name) copy"
        let source = plan.toSnapshot()
        let sessionID = UUID()

        let freshBlocks = source.sessions.flatMap(\.blocks).map(Self.freshCopy)
        var operations: [PlanOp] = [
            .setPlanMeta(name: .keep, goal: plan.goal.map(FieldEdit.set) ?? .keep, notes: plan.notes.map(FieldEdit.set) ?? .keep),
            .addSession(id: sessionID, name: "Workout", index: nil),
            .setCursor(sessionID: sessionID)
        ]
        operations += freshBlocks.map { .addBlock(sessionID: sessionID, block: $0, index: nil) }

        return createViaRepository(PlanMutation(operations: operations), name: name, context: context) {
            let copy = PlanRecord(name: name, goal: plan.goal, notes: plan.notes)
            let session = attachDefaultSession(to: copy)
            for block in plan.orderedBlocks {
                let blockCopy = PlanBlockRecord(order: block.order, kind: block.kind, label: block.label, rounds: block.rounds, restSeconds: block.restSeconds, sessionID: session.id)
                for exercise in block.orderedExercises {
                    let exerciseCopy = PlanExerciseRecord(order: exercise.order, name: exercise.name, cue: exercise.cue)
                    exerciseCopy.sets = exercise.orderedSets.map { set in
                        PlanSetRecord(
                            order: set.order, reps: set.reps, weight: set.weight, seconds: set.seconds,
                            targetMinKg: set.targetMinKg, targetMaxKg: set.targetMaxKg)
                    }
                    blockCopy.exercises.append(exerciseCopy)
                }
                copy.blocks.append(blockCopy)
            }
            return copy
        }
    }

    /// Recursively re-mints every id in `block` (and its exercises/sets) with a fresh `UUID` — the
    /// value-layer counterpart of the record-graph deep copy `duplicate` used to build by hand.
    private static func freshCopy(_ block: BlockSnapshot) -> BlockSnapshot {
        BlockSnapshot(
            id: UUID(),
            kind: block.kind,
            label: block.label,
            rounds: block.rounds,
            restSeconds: block.restSeconds,
            exercises: block.exercises.map { exercise in
                ExerciseSnapshot(
                    id: UUID(),
                    name: exercise.name,
                    cue: exercise.cue,
                    sets: exercise.sets.map { set in
                        SetSnapshot(
                            id: UUID(), reps: set.reps, weight: set.weight, seconds: set.seconds,
                            targetMinKg: set.targetMinKg, targetMaxKg: set.targetMaxKg)
                    }
                )
            }
        )
    }

    /// Creates and attaches a single default `PlanSessionRecord("Workout")` to a freshly built (not
    /// yet inserted) `PlanRecord`, and points `nextSessionID` at it — used only by the fallback
    /// closures below, for the (should-be-unreachable) case where `PlanEngine`/`PlanRepository`
    /// rejects a mutation this file built.
    @discardableResult
    private static func attachDefaultSession(to plan: PlanRecord) -> PlanSessionRecord {
        let session = PlanSessionRecord(order: 0, name: "Workout")
        session.plan = plan
        plan.sessions = [session]
        plan.nextSessionID = session.id
        return session
    }

    /// Shared plumbing for `createBlank`/`duplicate`/`createFromSession`: apply `mutation` via
    /// `PlanRepository.createPlan` (never activating — matches all three call sites' prior
    /// behavior) so plan creation has ONE mechanism and every new plan gets a baseline revision. The
    /// mutations these three build are well-formed by construction (fresh/self-consistent ids, valid
    /// `PlanOp`s), so `PlanEngine` should never actually reject them — `fallback` exists only so this
    /// non-throwing API can still return a usable `PlanRecord` in that should-be-unreachable case,
    /// mirroring each call site's pre-slice-8 direct-insert implementation.
    private static func createViaRepository(
        _ mutation: PlanMutation, name: String, context: ModelContext, fallback: () -> PlanRecord
    ) -> PlanRecord {
        if let plan = try? PlanRepository(context: context).createPlan(mutation, name: name, activate: false) {
            return plan
        }
        let plan = fallback()
        context.insert(plan)
        try? context.save()
        return plan
    }

    /// Builds a new plan from a completed `WorkoutRecord`'s prescribed values — "repeat this past
    /// session" without needing the coach. Groups exercises back into blocks by `groupLabel`
    /// (falling back to `blockName` for straight sets, which have no group label). Routed through
    /// `PlanRepository.createPlan` like `createBlank`/`duplicate` above.
    @discardableResult
    static func createFromSession(_ record: WorkoutRecord, context: ModelContext) -> PlanRecord {
        let name = "\(record.name) (from history)"
        let sessionID = UUID()

        var blockByKey: [String: BlockSnapshot] = [:]
        var order: [String] = []
        for exerciseRecord in record.exercises.sorted(by: { $0.order < $1.order }) {
            let kind: BlockKindSnapshot
            switch exerciseRecord.groupKind {
            case .straight: kind = .straight
            case .superset: kind = .superset
            case .circuit: kind = .circuit
            }
            let key = kind == .straight ? "straight-\(exerciseRecord.id)" : (exerciseRecord.groupLabel ?? exerciseRecord.blockName)

            let sortedSets = exerciseRecord.sets.sorted { $0.order < $1.order }
            var sets = sortedSets.map { set in
                SetSnapshot(
                    id: UUID(), reps: set.prescribedReps, weight: set.prescribedWeight,
                    seconds: set.prescribedSeconds, targetMinKg: set.prescribedTargetMinKg,
                    targetMaxKg: set.prescribedTargetMaxKg)
            }
            if sets.isEmpty {
                sets = [SetSnapshot(id: UUID(), reps: 10, weight: nil, seconds: nil)]
            }
            let exercise = ExerciseSnapshot(id: UUID(), name: exerciseRecord.name, cue: "", sets: sets)

            if var block = blockByKey[key] {
                block.exercises.append(exercise)
                block.rounds = max(block.rounds, sets.count)
                blockByKey[key] = block
            } else {
                order.append(key)
                blockByKey[key] = BlockSnapshot(
                    id: UUID(), kind: kind, label: exerciseRecord.groupLabel ?? exerciseRecord.blockName,
                    rounds: sets.count, restSeconds: nil, exercises: [exercise]
                )
            }
        }

        var blocks = order.compactMap { blockByKey[$0] }
        if blocks.isEmpty {
            let sets = [SetSnapshot(id: UUID(), reps: 10, weight: nil, seconds: nil)]
            let exercise = ExerciseSnapshot(id: UUID(), name: record.name, cue: "", sets: sets)
            blocks = [BlockSnapshot(id: UUID(), kind: .straight, label: record.name, rounds: 1, restSeconds: nil, exercises: [exercise])]
        }

        let mutation = PlanMutation(operations: [
            .setPlanMeta(name: .keep, goal: record.goal.map(FieldEdit.set) ?? .keep, notes: .keep),
            .addSession(id: sessionID, name: "Workout", index: nil),
            .setCursor(sessionID: sessionID)
        ] + blocks.map { .addBlock(sessionID: sessionID, block: $0, index: nil) })

        return createViaRepository(mutation, name: name, context: context) {
            let plan = PlanRecord(name: name, goal: record.goal)
            let session = attachDefaultSession(to: plan)
            for (index, blockSnapshot) in blocks.enumerated() {
                let blockCopy = PlanBlockRecord(
                    order: index, kind: PlanBlockKind(rawValue: blockSnapshot.kind.rawValue) ?? .straight,
                    label: blockSnapshot.label, rounds: blockSnapshot.rounds, restSeconds: blockSnapshot.restSeconds,
                    sessionID: session.id
                )
                for (exerciseIndex, exerciseSnapshot) in blockSnapshot.exercises.enumerated() {
                    let exerciseCopy = PlanExerciseRecord(order: exerciseIndex, name: exerciseSnapshot.name, cue: exerciseSnapshot.cue)
                    exerciseCopy.sets = exerciseSnapshot.sets.enumerated().map { setIndex, setSnapshot in
                        PlanSetRecord(
                            order: setIndex, reps: setSnapshot.reps, weight: setSnapshot.weight,
                            seconds: setSnapshot.seconds, targetMinKg: setSnapshot.targetMinKg,
                            targetMaxKg: setSnapshot.targetMaxKg)
                    }
                    blockCopy.exercises.append(exerciseCopy)
                }
                plan.blocks.append(blockCopy)
            }
            return plan
        }
    }

    /// Deletes `plan`. If it was the active plan, promotes the most recently created remaining plan
    /// to active so Today never dangles with no plan selected while any plan still exists.
    static func delete(_ plan: PlanRecord, context: ModelContext) {
        let wasActive = plan.isActive
        context.delete(plan)
        try? context.save()

        guard wasActive else { return }
        var descriptor = FetchDescriptor<PlanRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        if let next = try? context.fetch(descriptor).first {
            setActive(next, context: context)
        }
    }
}
