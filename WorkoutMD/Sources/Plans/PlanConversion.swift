import Foundation

/// Bridges the persisted `PlanRecord` graph (`PlanModels.swift`) to the in-memory shapes the runner
/// and Markdown export already know: `[WorkoutBlock]` (coarse — one representative target per
/// exercise, used for export/summary) and `[WorkoutStep]` (fine-grained — every prescribed set's own
/// reps/weight/seconds, which is what actually drives the runner via `WorkoutSession.init`).
extension PlanRecord {

    /// Full-fidelity flattening straight to pager steps, respecting each `PlanSetRecord`'s own
    /// target (so an edited, non-uniform rep scheme — e.g. a pyramid, or a coach-added drop set —
    /// shows up correctly). This is the conversion `WorkoutSession` is actually initialized from.
    func toWorkoutSteps() -> [WorkoutStep] {
        var result: [WorkoutStep] = []
        var moodIndex = 0
        var supersetLetterCount = 0

        for (blockIndex, block) in orderedBlocks.enumerated() {
            let exercises = block.orderedExercises

            switch block.kind {
            case .straight:
                guard let exerciseRecord = exercises.first else { continue }
                let sets = exerciseRecord.orderedSets
                guard !sets.isEmpty else { continue }
                let mood = MoodKey.atIndex(moodIndex)
                moodIndex += 1
                for (index, setRecord) in sets.enumerated() {
                    let exercise = Exercise(name: exerciseRecord.name, cue: exerciseRecord.cue, target: setRecord.asSetTarget, moodKey: mood)
                    let info = SetPageInfo(
                        exercise: exercise,
                        setNumber: index + 1,
                        totalSets: sets.count,
                        groupLabel: nil,
                        groupKind: nil,
                        round: nil,
                        totalRounds: nil,
                        miniMap: nil
                    )
                    result.append(WorkoutStep(blockIndex: blockIndex, blockName: block.label, moodKey: mood, page: .set(info), exerciseName: exerciseRecord.name))
                }

            case .superset, .circuit:
                guard !exercises.isEmpty else { continue }
                let groupKind: GroupKind = block.kind == .superset ? .superset : .circuit
                let letterPrefix: String?
                if block.kind == .superset {
                    letterPrefix = Self.letters[supersetLetterCount % Self.letters.count]
                    supersetLetterCount += 1
                } else {
                    letterPrefix = nil
                }
                let rounds = max(exercises.map(\.orderedSets.count).max() ?? block.rounds, 1)

                for round in 0..<rounds {
                    for (exIndex, exerciseRecord) in exercises.enumerated() {
                        let mood = MoodKey.atIndex(moodIndex + exIndex)
                        let sets = exerciseRecord.orderedSets
                        let setRecord = round < sets.count ? sets[round] : sets.last
                        let target = setRecord?.asSetTarget ?? .reps(count: 0, weight: nil)
                        let exercise = Exercise(name: exerciseRecord.name, cue: exerciseRecord.cue, target: target, moodKey: mood)
                        let miniMap = exercises.enumerated().map { idx, ex -> MiniMapItem in
                            MiniMapItem(
                                shortLabel: letterPrefix.map { "\($0)\(idx + 1)" } ?? "\(idx + 1)",
                                name: ex.name,
                                isCurrent: idx == exIndex
                            )
                        }
                        let info = SetPageInfo(
                            exercise: exercise,
                            setNumber: exIndex + 1,
                            totalSets: exercises.count,
                            groupLabel: block.label,
                            groupKind: groupKind,
                            round: round + 1,
                            totalRounds: rounds,
                            miniMap: miniMap
                        )
                        result.append(WorkoutStep(blockIndex: blockIndex, blockName: block.label, moodKey: mood, page: .set(info), exerciseName: exerciseRecord.name))
                    }

                    if let restSeconds = block.restSeconds, round < rounds - 1 {
                        let nextName = exercises.first?.name ?? ""
                        let restInfo = RestPageInfo(seconds: restSeconds, afterRound: round + 1, totalRounds: rounds, groupLabel: block.label, nextUpName: nextName)
                        result.append(WorkoutStep(blockIndex: blockIndex, blockName: block.label, moodKey: .rest, page: .rest(restInfo), exerciseName: nil))
                    }
                }
                moodIndex += exercises.count
            }
        }

        return result
    }

    /// Coarse conversion to `[WorkoutBlock]` — one representative target per exercise (its first
    /// prescribed set) — used where the finer per-set detail doesn't matter: `MarkdownGenerator
    /// .renderPlan` export and any other place that wants the plan's shape rather than its exact
    /// runner-page sequence.
    func toWorkoutBlocks() -> [WorkoutBlock] {
        var supersetLetterCount = 0
        return orderedBlocks.enumerated().map { index, block in
            let exercises = block.orderedExercises
            switch block.kind {
            case .straight:
                let exerciseRecord = exercises.first
                let sets = exerciseRecord?.orderedSets ?? []
                let target = sets.first?.asSetTarget ?? .reps(count: 0, weight: nil)
                let exercise = Exercise(name: exerciseRecord?.name ?? block.label, cue: exerciseRecord?.cue ?? "", target: target, moodKey: MoodKey.atIndex(index))
                return WorkoutBlock(name: block.label, kind: .straightSets(exercise: exercise, sets: max(sets.count, 1)))

            case .superset, .circuit:
                let groupKind: GroupKind = block.kind == .superset ? .superset : .circuit
                let letterPrefix: String?
                if block.kind == .superset {
                    letterPrefix = Self.letters[supersetLetterCount % Self.letters.count]
                    supersetLetterCount += 1
                } else {
                    letterPrefix = nil
                }
                let rounds = max(exercises.map(\.orderedSets.count).max() ?? block.rounds, 1)
                let exerciseModels = exercises.enumerated().map { i, e in
                    Exercise(name: e.name, cue: e.cue, target: e.orderedSets.first?.asSetTarget ?? .reps(count: 0, weight: nil), moodKey: MoodKey.atIndex(index + i))
                }
                return WorkoutBlock(
                    name: block.label,
                    kind: .group(kind: groupKind, label: block.label, letterPrefix: letterPrefix, exercises: exerciseModels, rounds: rounds, restSeconds: block.restSeconds)
                )
            }
        }
    }

    private static let letters = ["A", "B", "C", "D", "E", "F"]
}
