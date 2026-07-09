import SwiftUI
import Observation

// MARK: - Domain Models

/// A single exercise movement with its coaching cue and target for a set. `target` is `var` so the
/// coach and the reps stepper can edit upcoming sets live through the shared session.
struct Exercise: Identifiable {
    let id = UUID()
    let name: String
    let cue: String
    var target: SetTarget
    let moodKey: MoodKey
}

/// What the lifter is meant to hit for a given set: either a rep/weight target or a timed hold.
enum SetTarget {
    case reps(count: Int, weight: Double?)
    case timed(seconds: Int)

    var displayString: String {
        switch self {
        case .reps(let count, let weight):
            if let weight {
                return "\(count) reps · \(Int(weight)) lb"
            }
            return "\(count) reps"
        case .timed(let seconds):
            return "\(seconds) sec"
        }
    }

    var isTimed: Bool {
        if case .timed = self { return true }
        return false
    }

    var weight: Double? {
        if case .reps(_, let weight) = self { return weight }
        return nil
    }
}

/// How a block of work is organized.
enum GroupKind {
    case superset
    case circuit

    var label: String {
        switch self {
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        }
    }
}

/// Drives the per-page background color story so the pager feels alive as movements change.
enum MoodKey {
    case bench, inclinePress, row, facePull, cableFly, plank, rest
}

/// A named unit of a workout: either straight sets of one exercise, or a superset/circuit group.
struct WorkoutBlock: Identifiable {
    let id = UUID()
    let name: String
    let kind: BlockKind
}

enum BlockKind {
    case straightSets(exercise: Exercise, sets: Int)
    case group(kind: GroupKind, label: String, letterPrefix: String?, exercises: [Exercise], rounds: Int, restSeconds: Int?)
}

/// One movement's slot inside a group's inline mini-map (e.g. "A1 Incline DB Press").
struct MiniMapItem: Identifiable {
    let id = UUID()
    let shortLabel: String
    let name: String
    let isCurrent: Bool
}

// MARK: - Flattened Runner Steps

/// The runner works over a flat list of steps — one per pager page — derived from the blocks above.
/// `page` and `exerciseName` are mutable so the shared session can edit upcoming sets.
struct WorkoutStep: Identifiable {
    let id = UUID()
    let blockIndex: Int
    let blockName: String
    let moodKey: MoodKey
    var page: StepPage
    var exerciseName: String?
}

enum StepPage {
    case set(SetPageInfo)
    case rest(RestPageInfo)
}

struct SetPageInfo {
    var exercise: Exercise
    let setNumber: Int
    let totalSets: Int
    let groupLabel: String?
    let round: Int?
    let totalRounds: Int?
    let miniMap: [MiniMapItem]?
    var skipped: Bool = false
}

struct RestPageInfo {
    let seconds: Int
    let afterRound: Int
    let totalRounds: Int
    let groupLabel: String
    let nextUpName: String
}

// MARK: - Effort (RPE)

enum EffortScale {
    static let minRPE: Double = 6
    static let maxRPE: Double = 10

    /// Short label for an RPE value.
    static func label(for rpe: Double) -> String {
        switch Int(rpe.rounded()) {
        case ...6: return "Easy"
        case 7: return "Moderate"
        case 8: return "Hard"
        case 9: return "Very Hard"
        default: return "Max"
        }
    }

    /// Calm-to-hot color for a given RPE, used by the effort control and its committed state.
    static func color(for rpe: Double) -> Color {
        switch Int(rpe.rounded()) {
        case ...6: return Color(red: 0.20, green: 0.82, blue: 0.75)   // teal
        case 7: return Color(red: 0.35, green: 0.85, blue: 0.42)      // green
        case 8: return Color(red: 0.98, green: 0.76, blue: 0.22)      // amber
        case 9: return Color(red: 0.98, green: 0.52, blue: 0.18)      // orange
        default: return Color(red: 0.96, green: 0.28, blue: 0.28)     // red
        }
    }
}

// MARK: - Coach transcript

struct CoachMessage: Identifiable {
    enum Kind { case coach, user, diff }
    let id = UUID()
    let kind: Kind
    let text: String
}

/// Summary shown on the Done screen at the end of a session.
struct SessionSummary {
    let totalSets: Int
    let loggedSets: Int
    let averageRPE: Double?

    var averageEffortLabel: String {
        guard let averageRPE else { return "—" }
        return "\(EffortScale.label(for: averageRPE)) · RPE \(String(format: "%.1f", averageRPE))"
    }
}

// MARK: - Shared Observable Session

/// The single source of truth for a live workout. The runner, the effort control, the reps stepper,
/// and the coach all read and mutate this one object (injected via `.environment`), so an edit made
/// anywhere reflects everywhere — including the runner's upcoming pages.
@Observable
final class WorkoutSession {
    var steps: [WorkoutStep]
    var currentStepID: WorkoutStep.ID?
    /// Committed effort per set, as RPE 6–10.
    var rpe: [WorkoutStep.ID: Double] = [:]
    /// Coach transcript per exercise name.
    var transcripts: [String: [CoachMessage]] = [:]
    /// Exercises the coach has offered a "Deload 2 weeks" follow-up for.
    var offerDeload: Set<String> = []
    /// Exercises marked to deload / skip upcoming sessions.
    var deloaded: Set<String> = []

    init(steps: [WorkoutStep] = MockWorkout.steps) {
        self.steps = steps
        self.currentStepID = steps.first?.id
    }

    // MARK: Lookups

    var currentIndex: Int? {
        guard let currentStepID else { return nil }
        return steps.firstIndex { $0.id == currentStepID }
    }

    var currentStep: WorkoutStep? {
        guard let idx = currentIndex else { return nil }
        return steps[idx]
    }

    /// The exercise the coach is scoped to: the current set's exercise, or for a rest page the
    /// next-up movement.
    var currentExerciseName: String? {
        guard let step = currentStep else { return nil }
        switch step.page {
        case .set(let info): return info.exercise.name
        case .rest(let info): return info.nextUpName
        }
    }

    func transcript(for exercise: String) -> [CoachMessage] {
        transcripts[exercise] ?? []
    }

    // MARK: Effort

    func setEffort(_ value: Double, for id: WorkoutStep.ID) {
        rpe[id] = value
    }

    // MARK: Reps stepper edit

    func adjustReps(forStepID id: WorkoutStep.ID, delta: Int) {
        guard let idx = steps.firstIndex(where: { $0.id == id }),
              case .set(var info) = steps[idx].page,
              case .reps(let count, let weight) = info.exercise.target else { return }
        let newCount = max(0, count + delta)
        info.exercise.target = .reps(count: newCount, weight: weight)
        steps[idx].page = .set(info)
    }

    // MARK: Skip

    func skip(stepID id: WorkoutStep.ID) {
        guard let idx = steps.firstIndex(where: { $0.id == id }),
              case .set(var info) = steps[idx].page else { return }
        info.skipped = true
        steps[idx].page = .set(info)
    }

    // MARK: Coach policy

    /// Runs the scripted keyword policy for a plain-language note, appending transcript lines and
    /// applying a concrete edit to upcoming sets.
    func sendCoachMessage(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let name = currentExerciseName else { return }

        append(CoachMessage(kind: .user, text: text), to: name)
        let lower = text.lowercased()

        if contains(lower, ["pain", "hurt", "weird", "tweak", "back", "knee", "shoulder", "elbow"]) {
            append(CoachMessage(kind: .coach, text: "Sharp or dull? Cut your next set to 50%."), to: name)
            appendWeightDiff(for: name, factor: 0.5)
            offerDeload.insert(name)
        } else if contains(lower, ["tired", "gassed", "fatigued", "exhausted", "done"]) {
            append(CoachMessage(kind: .coach, text: "Dropping your last set. Keep rest tight."), to: name)
            skipLastRemainingSet(for: name)
        } else if contains(lower, ["too easy", "easy", "light"]) {
            append(CoachMessage(kind: .coach, text: "Adding 5 lb next set."), to: name)
            appendWeightDelta(for: name, delta: 5)
        } else if contains(lower, ["great", "strong", "good", "solid"]) {
            append(CoachMessage(kind: .coach, text: "Good. Holding the plan."), to: name)
        } else {
            append(CoachMessage(kind: .coach, text: "Noted."), to: name)
        }
    }

    func applyDeload() {
        guard let name = currentExerciseName else { return }
        deloaded.insert(name)
        offerDeload.remove(name)
        append(CoachMessage(kind: .diff, text: "Program note: deload \(name) 2 weeks, ease back in."), to: name)
    }

    /// One quiet opener so the transcript has context when first opened for an exercise.
    func seedTranscriptIfNeeded(for exercise: String) {
        guard transcripts[exercise] == nil else { return }
        transcripts[exercise] = [
            CoachMessage(kind: .coach, text: "On \(exercise). Tell me how it feels.")
        ]
    }

    // MARK: Private helpers

    private func append(_ message: CoachMessage, to exercise: String) {
        transcripts[exercise, default: []].append(message)
    }

    private func contains(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private func nextSetIndex(ofExercise name: String, afterCurrent: Bool) -> Int? {
        let start = (afterCurrent ? (currentIndex ?? -1) + 1 : 0)
        guard start >= 0, start < steps.count else { return nil }
        for i in start..<steps.count {
            if case .set(let info) = steps[i].page, info.exercise.name == name, !info.skipped {
                return i
            }
        }
        return nil
    }

    private func appendWeightDiff(for name: String, factor: Double) {
        guard let idx = nextSetIndex(ofExercise: name, afterCurrent: true),
              case .set(var info) = steps[idx].page,
              case .reps(let count, let weight?) = info.exercise.target else {
            append(CoachMessage(kind: .diff, text: "Next \(name): ease off the load"), to: name)
            return
        }
        let newWeight = roundedToFive(weight * factor)
        info.exercise.target = .reps(count: count, weight: newWeight)
        steps[idx].page = .set(info)
        append(CoachMessage(kind: .diff, text: "Next \(name): \(Int(weight)) → \(Int(newWeight)) lb"), to: name)
    }

    private func appendWeightDelta(for name: String, delta: Double) {
        guard let idx = nextSetIndex(ofExercise: name, afterCurrent: true),
              case .set(var info) = steps[idx].page,
              case .reps(let count, let weight?) = info.exercise.target else {
            append(CoachMessage(kind: .diff, text: "Next \(name): no load to add"), to: name)
            return
        }
        let newWeight = weight + delta
        info.exercise.target = .reps(count: count, weight: newWeight)
        steps[idx].page = .set(info)
        append(CoachMessage(kind: .diff, text: "Next \(name): \(Int(weight)) → \(Int(newWeight)) lb"), to: name)
    }

    private func skipLastRemainingSet(for name: String) {
        let start = currentIndex ?? 0
        guard start < steps.count else { return }
        var lastIdx: Int?
        for i in start..<steps.count {
            if case .set(let info) = steps[i].page, info.exercise.name == name, !info.skipped {
                lastIdx = i
            }
        }
        guard let idx = lastIdx, case .set(var info) = steps[idx].page else {
            append(CoachMessage(kind: .diff, text: "No \(name) sets left to drop"), to: name)
            return
        }
        info.skipped = true
        steps[idx].page = .set(info)
        append(CoachMessage(kind: .diff, text: "Skipping last \(name) set"), to: name)
    }

    private func roundedToFive(_ value: Double) -> Double {
        (value / 5).rounded() * 5
    }

    // MARK: Summary

    func buildSummary() -> SessionSummary {
        let setSteps = steps.filter {
            if case .set = $0.page { return true }
            return false
        }
        let logged = setSteps.filter {
            if case .set(let info) = $0.page { return !info.skipped }
            return false
        }.count
        let values = setSteps.compactMap { rpe[$0.id] }
        let average: Double? = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        return SessionSummary(totalSets: setSteps.count, loggedSets: logged, averageRPE: average)
    }
}

// MARK: - Mock Workout Data

enum MockWorkout {
    static let name = "Upper Body A"
    static let summary = "3 blocks · ~45 min · Hypertrophy"

    static let blocks: [WorkoutBlock] = {
        let bench = Exercise(
            name: "Bench Press",
            cue: "Control the eccentric, 2s down. Leave 2 in the tank.",
            target: .reps(count: 10, weight: 135),
            moodKey: .bench
        )

        let inclineDB = Exercise(
            name: "Incline DB Press",
            cue: "Squeeze at the top. Stop 1–2 reps short.",
            target: .reps(count: 12, weight: 50),
            moodKey: .inclinePress
        )
        let row = Exercise(
            name: "Barbell Row",
            cue: "Flat back. Drive elbows to hips.",
            target: .reps(count: 10, weight: 135),
            moodKey: .row
        )

        let facePull = Exercise(
            name: "Face Pull",
            cue: "High elbows, pull to the eyes.",
            target: .reps(count: 15, weight: nil),
            moodKey: .facePull
        )
        let cableFly = Exercise(
            name: "Cable Fly",
            cue: "Long arc, feel the stretch.",
            target: .reps(count: 12, weight: nil),
            moodKey: .cableFly
        )
        let plank = Exercise(
            name: "Plank",
            cue: "Ribs down, glutes tight.",
            target: .timed(seconds: 45),
            moodKey: .plank
        )

        return [
            WorkoutBlock(name: "Bench Press", kind: .straightSets(exercise: bench, sets: 3)),
            WorkoutBlock(
                name: "Superset A",
                kind: .group(kind: .superset, label: "Superset A", letterPrefix: "A", exercises: [inclineDB, row], rounds: 3, restSeconds: 60)
            ),
            WorkoutBlock(
                name: "Circuit",
                kind: .group(kind: .circuit, label: "Circuit", letterPrefix: nil, exercises: [facePull, cableFly, plank], rounds: 3, restSeconds: 45)
            )
        ]
    }()

    static var steps: [WorkoutStep] { flatten(blocks: blocks) }

    /// Turns the block list into the flat sequence of pager pages, inserting rest pages between
    /// rounds of a group (but never after the final round).
    private static func flatten(blocks: [WorkoutBlock]) -> [WorkoutStep] {
        var result: [WorkoutStep] = []

        for (blockIndex, block) in blocks.enumerated() {
            switch block.kind {
            case .straightSets(let exercise, let sets):
                for setNumber in 1...sets {
                    let info = SetPageInfo(
                        exercise: exercise,
                        setNumber: setNumber,
                        totalSets: sets,
                        groupLabel: nil,
                        round: nil,
                        totalRounds: nil,
                        miniMap: nil
                    )
                    result.append(WorkoutStep(blockIndex: blockIndex, blockName: block.name, moodKey: exercise.moodKey, page: .set(info), exerciseName: exercise.name))
                }

            case .group(_, let label, let letterPrefix, let exercises, let rounds, let restSeconds):
                for round in 1...rounds {
                    for (exIndex, exercise) in exercises.enumerated() {
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
                            groupLabel: label,
                            round: round,
                            totalRounds: rounds,
                            miniMap: miniMap
                        )
                        result.append(WorkoutStep(blockIndex: blockIndex, blockName: block.name, moodKey: exercise.moodKey, page: .set(info), exerciseName: exercise.name))
                    }

                    if let restSeconds, round < rounds {
                        let nextName = exercises.first?.name ?? ""
                        let restInfo = RestPageInfo(
                            seconds: restSeconds,
                            afterRound: round,
                            totalRounds: rounds,
                            groupLabel: label,
                            nextUpName: nextName
                        )
                        result.append(WorkoutStep(blockIndex: blockIndex, blockName: block.name, moodKey: .rest, page: .rest(restInfo), exerciseName: nil))
                    }
                }
            }
        }

        return result
    }
}
