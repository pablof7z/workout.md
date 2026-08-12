import Foundation
import SwiftData

// MARK: - Durable history schema
//
// A completed `WorkoutSession` (the live, in-memory, `@Observable` truth used by the runner and
// coach) is snapshotted into this SwiftData graph once the user finishes a workout, so history
// survives app restarts. The shape mirrors the product spec's tracking requirements: per set, both
// the prescribed target and the actual result, RPE, skip/substitution flags, and notes; per
// exercise, its block and group context (straight sets vs. superset/circuit + round); per workout,
// the coach transcript and any adjustments the coach applied.
//
// `WorkoutSession` itself is never persisted directly — see `WorkoutSession.makeRecord` below,
// which bridges the two without ripping out the live session model.

/// How a set's parent block was organized. Mirrors `GroupKind` plus a "straight sets" case, stored
/// as a plain `String` (via `RawRepresentable`) so the SwiftData schema stays simple and stable.
enum RecordGroupKind: String, Codable {
    case straight
    case superset
    case circuit

    var label: String {
        switch self {
        case .straight: return "Straight Sets"
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        }
    }
}

/// Mirrors `CoachMessage.Kind` for the persisted transcript.
enum RecordCoachKind: String, Codable {
    case coach
    case user
    case diff
}

/// One completed workout session: date/time, workout name, goal, and everything logged during it.
@Model
final class WorkoutRecord {
    @Attribute(.unique) var id: UUID
    /// The plan this workout was started from. Nullable so existing history migrates cleanly and
    /// imported legacy sessions can remain honestly unlinked rather than relying on a name match.
    var planID: UUID?
    var date: Date
    var name: String
    var goal: String?

    var totalSets: Int
    var loggedSets: Int
    var averageRPE: Double?
    var heartRateSensorName: String?

    /// True for the couple of seed sessions shown on first run so History isn't empty. Never set by
    /// a real completed workout.
    var isMock: Bool

    @Relationship(deleteRule: .cascade, inverse: \ExerciseRecord.workout)
    var exercises: [ExerciseRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \CoachNoteRecord.workout)
    var coachNotes: [CoachNoteRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \HeartRateSampleRecord.workout)
    var heartRateSamples: [HeartRateSampleRecord] = []

    init(
        id: UUID = UUID(),
        planID: UUID? = nil,
        date: Date = .now,
        name: String,
        goal: String? = nil,
        totalSets: Int = 0,
        loggedSets: Int = 0,
        averageRPE: Double? = nil,
        heartRateSensorName: String? = nil,
        isMock: Bool = false
    ) {
        self.id = id
        self.planID = planID
        self.date = date
        self.name = name
        self.goal = goal
        self.totalSets = totalSets
        self.loggedSets = loggedSets
        self.averageRPE = averageRPE
        self.heartRateSensorName = heartRateSensorName
        self.isMock = isMock
    }

    /// Terse one-line summary for a History list row, e.g. "9/9 sets · avg RPE 7.8".
    var oneLineSummary: String {
        var parts = ["\(loggedSets)/\(totalSets) sets"]
        if let averageRPE {
            parts.append("avg RPE \(MarkdownGenerator.oneDecimal(averageRPE))")
        }
        return parts.joined(separator: " · ")
    }

    var averageHeartRate: Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        let total = heartRateSamples.reduce(0) { $0 + $1.beatsPerMinute }
        return Int((Double(total) / Double(heartRateSamples.count)).rounded())
    }

    var minimumHeartRate: Int? {
        heartRateSamples.map(\.beatsPerMinute).min()
    }

    var maximumHeartRate: Int? {
        heartRateSamples.map(\.beatsPerMinute).max()
    }
}

/// One timestamped Polar heart-rate reading persisted with its completed workout.
@Model
final class HeartRateSampleRecord {
    var id: UUID
    var timestamp: Date
    var beatsPerMinute: Int
    var workout: WorkoutRecord?

    init(id: UUID = UUID(), timestamp: Date, beatsPerMinute: Int) {
        self.id = id
        self.timestamp = timestamp
        self.beatsPerMinute = beatsPerMinute
    }
}

/// One exercise's worth of sets within a completed workout — either from a straight-sets block or
/// one movement inside a superset/circuit group.
@Model
final class ExerciseRecord {
    var id: UUID
    /// Position within the workout, for stable display ordering.
    var order: Int
    var name: String
    var blockName: String
    var groupKind: RecordGroupKind
    /// e.g. "Superset A" — nil for straight sets.
    var groupLabel: String?

    var workout: WorkoutRecord?

    @Relationship(deleteRule: .cascade, inverse: \SetRecord.exercise)
    var sets: [SetRecord] = []

    init(
        id: UUID = UUID(),
        order: Int,
        name: String,
        blockName: String,
        groupKind: RecordGroupKind,
        groupLabel: String? = nil
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.blockName = blockName
        self.groupKind = groupKind
        self.groupLabel = groupLabel
    }
}

/// One logged set: what was prescribed, what actually happened, and any deviation from plan.
@Model
final class SetRecord {
    var id: UUID
    /// Position within the exercise, for stable display ordering.
    var order: Int
    var setNumber: Int
    var round: Int?
    var totalRounds: Int?

    // Prescribed (the plan).
    var prescribedReps: Int?
    var prescribedWeight: Double?
    var prescribedSeconds: Int?
    var prescribedTargetMinKg: Double?
    var prescribedTargetMaxKg: Double?

    // Actual (what happened). Nil when skipped.
    var actualReps: Int?
    var actualWeight: Double?
    var actualSeconds: Int?
    var actualPeakKg: Double?
    var actualAverageKg: Double?
    var actualTimeInTargetSeconds: Double?

    var rpe: Double?
    var skipped: Bool
    var substituted: Bool
    var substitutedName: String?
    var notes: String?
    /// The originating `WorkoutStep.id` this set was logged against — added (slice 5,
    /// domain-primitives.md §8) for traceability once `makeRecord` joins prescribed/actual by
    /// stable identity instead of positional `zip`. Nullable/additive: existing rows lightweight-
    /// migrate for free, and `nil` just means "logged before this field existed."
    var sourceStepID: UUID?

    var exercise: ExerciseRecord?

    init(
        id: UUID = UUID(),
        order: Int,
        setNumber: Int,
        round: Int? = nil,
        totalRounds: Int? = nil,
        prescribedReps: Int? = nil,
        prescribedWeight: Double? = nil,
        prescribedSeconds: Int? = nil,
        prescribedTargetMinKg: Double? = nil,
        prescribedTargetMaxKg: Double? = nil,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        actualSeconds: Int? = nil,
        actualPeakKg: Double? = nil,
        actualAverageKg: Double? = nil,
        actualTimeInTargetSeconds: Double? = nil,
        rpe: Double? = nil,
        skipped: Bool = false,
        substituted: Bool = false,
        substitutedName: String? = nil,
        notes: String? = nil,
        sourceStepID: UUID? = nil
    ) {
        self.id = id
        self.order = order
        self.setNumber = setNumber
        self.round = round
        self.totalRounds = totalRounds
        self.prescribedReps = prescribedReps
        self.prescribedWeight = prescribedWeight
        self.prescribedSeconds = prescribedSeconds
        self.prescribedTargetMinKg = prescribedTargetMinKg
        self.prescribedTargetMaxKg = prescribedTargetMaxKg
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.actualSeconds = actualSeconds
        self.actualPeakKg = actualPeakKg
        self.actualAverageKg = actualAverageKg
        self.actualTimeInTargetSeconds = actualTimeInTargetSeconds
        self.rpe = rpe
        self.skipped = skipped
        self.substituted = substituted
        self.substitutedName = substitutedName
        self.notes = notes
        self.sourceStepID = sourceStepID
    }

    /// "Set 2" or, inside a group, "R2/3 · Set 1".
    var label: String {
        if let round, let totalRounds {
            return "R\(round)/\(totalRounds) · Set \(setNumber)"
        }
        return "Set \(setNumber)"
    }

    var prescribedDisplay: String {
        if let prescribedSeconds, let prescribedTargetMinKg, let prescribedTargetMaxKg {
            return "\(prescribedSeconds) sec · \(kg(prescribedTargetMinKg))–\(kg(prescribedTargetMaxKg)) kg"
        }
        if let prescribedSeconds {
            return "\(prescribedSeconds) sec"
        }
        guard let prescribedReps else { return "—" }
        if let prescribedWeight {
            return "\(prescribedReps) reps · \(Int(prescribedWeight)) lb"
        }
        return "\(prescribedReps) reps"
    }

    var actualDisplay: String {
        if skipped { return "Skipped" }
        if let actualPeakKg, let actualAverageKg, let actualSeconds {
            return "\(actualSeconds) sec · peak \(kg(actualPeakKg)) kg · avg \(kg(actualAverageKg)) kg"
        }
        if let actualSeconds {
            return "\(actualSeconds) sec"
        }
        guard let actualReps else { return "—" }
        if let actualWeight {
            return "\(actualReps) reps · \(Int(actualWeight)) lb"
        }
        return "\(actualReps) reps"
    }

    /// Whether this set's actual result diverges from what was prescribed — skipped, substituted,
    /// or a different rep count / weight than planned.
    var isDeviation: Bool {
        if skipped || substituted { return true }
        if let prescribedReps, let actualReps, prescribedReps != actualReps { return true }
        if let prescribedWeight, let actualWeight, prescribedWeight != actualWeight { return true }
        return false
    }

    private func kg(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// One line of the coach transcript for a completed workout, tagged with which exercise it was
/// scoped to (nil for a general/session-level note).
///
/// `workout` is optional so the live coach can persist a turn the moment it happens — as a
/// standalone note not yet (or never) attached to a finished `WorkoutRecord` — which is what gives
/// `CoachController` cross-launch memory: it re-reads these by `exerciseName` to seed
/// `send_message`'s `history_json` even before the session that produced them is saved to history.
@Model
final class CoachNoteRecord {
    var id: UUID
    /// Chronological position across the whole session's transcript (only meaningful once bridged
    /// into a `WorkoutRecord.coachNotes` — see `WorkoutSession.makeRecord`). Standalone live notes
    /// (`workout == nil`) sort by `date` instead.
    var order: Int
    var kind: RecordCoachKind
    var text: String
    var exerciseName: String?
    /// When this line was actually said/applied — added so the live coach can reconstruct
    /// conversation history in chronological order across turns and app launches, independent of
    /// whether it's yet attached to a finished `WorkoutRecord`.
    var date: Date
    /// The `PlanRecord.id` active when this note was said, if any — added (p2) so
    /// `CoachController.historyJSON(for:planID:...)` can scope memory to the plan it was said under
    /// instead of a bare `exerciseName` bleeding "Bench Press" notes across every plan the athlete has
    /// ever run. `nil` for notes persisted before this field existed (or with no active plan at the
    /// time) — those are treated as plan-agnostic and still included for any plan, rather than
    /// silently dropped.
    var planID: UUID?

    var workout: WorkoutRecord?

    init(
        id: UUID = UUID(),
        order: Int,
        kind: RecordCoachKind,
        text: String,
        exerciseName: String? = nil,
        date: Date = .now,
        planID: UUID? = nil
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.text = text
        self.exerciseName = exerciseName
        self.date = date
        self.planID = planID
    }
}

// MARK: - Bridging a finished `WorkoutSession` into the SwiftData graph

extension WorkoutSession {
    /// Snapshots this session into a `WorkoutRecord` graph. Does not insert into any
    /// `ModelContext` — the caller does that, so it controls persistence timing (the app calls this
    /// when the user reaches the Done screen).
    ///
    /// Prescribed values come from `prescribedSteps` (captured at session start, before any coach
    /// edit or reps-stepper nudge); actual values come from the live `steps` as they stand when the
    /// workout finishes. For a timed set with no dedicated "log actual duration" control in this
    /// prototype, a completed (non-skipped) hold is recorded as having run the prescribed duration.
    ///
    /// Joins the two by STABLE `WorkoutStep.id` (domain-primitives.md §8), not `zip(prescribedSteps,
    /// steps)` — a positional pairing that a structural live edit (coach `addSet`/`removeSet`/
    /// reorder) could silently misalign, corrupting prescribed-vs-actual history for every set after
    /// the edit. Iterating `steps` (the live/actual array) and looking each one up by id means:
    /// - a step present in both → prescribed from the frozen snapshot, actual from the live step, as
    ///   before;
    /// - a step ADDED live (its id isn't in `prescribedSteps`, e.g. the coach's `addSet`) → no
    ///   prescribed values (all `prescribed*` fields stay `nil` — an honest "this wasn't planned",
    ///   not a guess), actual from the live step;
    /// - a step REMOVED live (its id is in `prescribedSteps` but no longer in `steps`) → simply never
    ///   visited by this loop, so it isn't emitted — it was never part of the actual session.
    func makeRecord(workoutName: String, goal: String?, date: Date = .now) -> WorkoutRecord {
        let summary = buildSummary()
        let record = WorkoutRecord(
            planID: activePlan?.id,
            date: date,
            name: workoutName,
            goal: goal,
            totalSets: summary.totalSets,
            loggedSets: summary.loggedSets,
            averageRPE: summary.averageRPE,
            heartRateSensorName: heartRateSensorName
        )

        record.heartRateSamples = heartRateSamples.map {
            HeartRateSampleRecord(timestamp: $0.timestamp, beatsPerMinute: $0.beatsPerMinute)
        }

        struct ExerciseKey: Hashable {
            let blockIndex: Int
            let name: String
        }

        let prescribedByID: [WorkoutStep.ID: WorkoutStep] = Dictionary(
            uniqueKeysWithValues: prescribedSteps.map { ($0.id, $0) }
        )

        var exerciseByKey: [ExerciseKey: ExerciseRecord] = [:]
        var orderedExercises: [ExerciseRecord] = []
        var setOrder = 0

        for actualStep in steps {
            guard case .set(let actualInfo) = actualStep.page else { continue }

            let prescribedInfo: SetPageInfo? = {
                guard case .set(let info)? = prescribedByID[actualStep.id]?.page else { return nil }
                return info
            }()

            let key = ExerciseKey(blockIndex: actualStep.blockIndex, name: actualInfo.exercise.name)
            let exerciseRecord: ExerciseRecord
            if let existing = exerciseByKey[key] {
                exerciseRecord = existing
            } else {
                let groupKind: RecordGroupKind
                switch prescribedInfo?.groupKind ?? actualInfo.groupKind {
                case .superset: groupKind = .superset
                case .circuit: groupKind = .circuit
                case nil: groupKind = .straight
                }
                exerciseRecord = ExerciseRecord(
                    order: orderedExercises.count,
                    name: actualInfo.exercise.name,
                    blockName: actualStep.blockName,
                    groupKind: groupKind,
                    groupLabel: prescribedInfo?.groupLabel ?? actualInfo.groupLabel
                )
                exerciseByKey[key] = exerciseRecord
                orderedExercises.append(exerciseRecord)
            }

            let setRecord = SetRecord(
                order: setOrder,
                setNumber: prescribedInfo?.setNumber ?? actualInfo.setNumber,
                round: prescribedInfo?.round ?? actualInfo.round,
                totalRounds: prescribedInfo?.totalRounds ?? actualInfo.totalRounds,
                rpe: rpe[actualStep.id],
                skipped: actualInfo.skipped,
                sourceStepID: actualStep.id
            )
            setOrder += 1

            if let prescribedInfo {
                switch prescribedInfo.exercise.target {
                case .reps(let count, let weight):
                    setRecord.prescribedReps = count
                    setRecord.prescribedWeight = weight
                case .timed(let seconds):
                    setRecord.prescribedSeconds = seconds
                case .tindeq(let seconds, let targetMinKg, let targetMaxKg):
                    setRecord.prescribedSeconds = seconds
                    setRecord.prescribedTargetMinKg = targetMinKg
                    setRecord.prescribedTargetMaxKg = targetMaxKg
                }
            }

            if !actualInfo.skipped {
                switch actualInfo.exercise.target {
                case .reps(let count, let weight):
                    setRecord.actualReps = count
                    setRecord.actualWeight = weight
                case .timed(let seconds):
                    setRecord.actualSeconds = seconds
                case .tindeq(let seconds, _, _):
                    let result = tindeqResults[actualStep.id]
                    setRecord.actualSeconds = Int((result?.holdSeconds ?? Double(seconds)).rounded())
                    setRecord.actualPeakKg = result?.peakKg
                    setRecord.actualAverageKg = result?.averageKg
                    setRecord.actualTimeInTargetSeconds = result?.timeInTargetSeconds
                }
            }

            exerciseRecord.sets.append(setRecord)
        }

        record.exercises = orderedExercises

        let allMessages = transcripts
            .flatMap { exerciseName, messages in messages.map { (exerciseName, $0) } }
            .sorted { $0.1.date < $1.1.date }

        record.coachNotes = allMessages.enumerated().map { index, entry in
            let (exerciseName, message) = entry
            let kind: RecordCoachKind
            switch message.kind {
            case .coach: kind = .coach
            case .user: kind = .user
            case .diff: kind = .diff
            }
            return CoachNoteRecord(order: index, kind: kind, text: message.text, exerciseName: exerciseName, date: message.date, planID: activePlan?.id)
        }

        return record
    }
}
