import Foundation
import SwiftData

/// CRUD + lifecycle operations over `PlanRecord`, mirroring the shape of `MockHistory`'s
/// `seedIfNeeded` (a namespace of static functions over an explicit `ModelContext`, rather than an
/// `@Observable` service) since every call site already has a `ModelContext` in scope (a SwiftUI
/// `@Environment` or a background task's own context) and there's no other shared state to own.
enum PlanStore {

    /// Seeds the one real default plan (`DefaultPlanSeed`) on first run. No-op if any `PlanRecord`
    /// already exists — never overwrites a user's real plans.
    static func seedDefaultIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<PlanRecord>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }
        context.insert(DefaultPlanSeed.makePlanRecord())
        try? context.save()
    }

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

    @discardableResult
    static func createBlank(name: String, goal: String?, context: ModelContext) -> PlanRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = PlanRecord(name: trimmedName.isEmpty ? "New Plan" : trimmedName, goal: goal)
        context.insert(plan)
        try? context.save()
        return plan
    }

    /// Deep-copies `plan`'s whole block/exercise/set graph under a new identity — never active by
    /// default, so duplicating doesn't silently swap out what Today runs.
    @discardableResult
    static func duplicate(_ plan: PlanRecord, newName: String? = nil, context: ModelContext) -> PlanRecord {
        let copy = PlanRecord(name: newName?.isEmpty == false ? newName! : "\(plan.name) copy", goal: plan.goal, notes: plan.notes)
        for block in plan.orderedBlocks {
            let blockCopy = PlanBlockRecord(order: block.order, kind: block.kind, label: block.label, rounds: block.rounds, restSeconds: block.restSeconds)
            for exercise in block.orderedExercises {
                let exerciseCopy = PlanExerciseRecord(order: exercise.order, name: exercise.name, cue: exercise.cue)
                exerciseCopy.sets = exercise.orderedSets.map { set in
                    PlanSetRecord(order: set.order, reps: set.reps, weight: set.weight, seconds: set.seconds)
                }
                blockCopy.exercises.append(exerciseCopy)
            }
            copy.blocks.append(blockCopy)
        }
        context.insert(copy)
        try? context.save()
        return copy
    }

    /// Builds a new plan from a completed `WorkoutRecord`'s prescribed values — "repeat this past
    /// session" without needing the coach. Groups exercises back into blocks by `groupLabel`
    /// (falling back to `blockName` for straight sets, which have no group label).
    @discardableResult
    static func createFromSession(_ record: WorkoutRecord, context: ModelContext) -> PlanRecord {
        let plan = PlanRecord(name: "\(record.name) (from history)", goal: record.goal)

        var blockByKey: [String: PlanBlockRecord] = [:]
        var nextOrder = 0
        for exerciseRecord in record.exercises.sorted(by: { $0.order < $1.order }) {
            let kind: PlanBlockKind
            switch exerciseRecord.groupKind {
            case .straight: kind = .straight
            case .superset: kind = .superset
            case .circuit: kind = .circuit
            }
            let key = kind == .straight ? "straight-\(exerciseRecord.id)" : (exerciseRecord.groupLabel ?? exerciseRecord.blockName)

            let block: PlanBlockRecord
            if let existing = blockByKey[key] {
                block = existing
            } else {
                block = PlanBlockRecord(order: nextOrder, kind: kind, label: exerciseRecord.groupLabel ?? exerciseRecord.blockName)
                nextOrder += 1
                blockByKey[key] = block
                plan.blocks.append(block)
            }

            let exercise = PlanExerciseRecord(order: block.exercises.count, name: exerciseRecord.name)
            let sortedSets = exerciseRecord.sets.sorted { $0.order < $1.order }
            exercise.sets = sortedSets.enumerated().map { index, set in
                PlanSetRecord(order: index, reps: set.prescribedReps, weight: set.prescribedWeight, seconds: set.prescribedSeconds)
            }
            if exercise.sets.isEmpty {
                exercise.sets = [PlanSetRecord(order: 0, reps: 10, weight: nil)]
            }
            block.rounds = max(block.rounds, exercise.sets.count)
            block.exercises.append(exercise)
        }

        if plan.blocks.isEmpty {
            let block = PlanBlockRecord(order: 0, kind: .straight, label: record.name)
            let exercise = PlanExerciseRecord(order: 0, name: record.name)
            exercise.sets = [PlanSetRecord(order: 0, reps: 10, weight: nil)]
            block.exercises = [exercise]
            plan.blocks = [block]
        }

        context.insert(plan)
        try? context.save()
        return plan
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
