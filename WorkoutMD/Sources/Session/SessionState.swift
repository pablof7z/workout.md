import Foundation
import SwiftData

// MARK: - SessionState
//
// See `docs/architecture/domain-primitives.md` §8. A plan-INDEPENDENT `Codable` mirror of a live
// `WorkoutSession` — everything needed to fully rebuild the session WITHOUT re-reading the
// originating `PlanRecord` (which may have changed, or been deleted, since the session started).
// `SessionState.from(_:)` snapshots a live session; `WorkoutSession.restore(from:modelContext:)`
// (below) rebuilds one. `ActiveSessionStore` is what actually persists/loads this snapshot as
// `ActiveSessionRecord.stateJSON`.
struct SessionState: Codable {

    /// One `WorkoutStep`, id-preserving.
    struct StepState: Codable {
        let id: UUID
        let blockIndex: Int
        let blockName: String
        /// `MoodKey`'s wire form — see `MoodKey.wireKey`/`MoodKey.init(wireKey:)` below (`MoodKey`
        /// itself isn't `Codable`, so this file owns the string mapping rather than reaching into
        /// `Models.swift` to add one).
        let moodKey: String
        let exerciseName: String?
        let page: PageState
    }

    /// Mirrors `StepPage` — a set page or a rest page.
    enum PageState: Codable {
        case set(SetPageState)
        case rest(RestPageState)
    }

    /// Mirrors `SetPageInfo`, plus the frozen PRESCRIBED target for this same step (looked up from
    /// `WorkoutSession.prescribedSteps` by this step's id at snapshot time — `nil` for a step that
    /// has no prescribed counterpart, i.e. one added live via the coach's `addSet`).
    struct SetPageState: Codable {
        var exerciseName: String
        var exerciseCue: String
        /// The live/actual target — reps+weight, or `seconds` alone for a timed hold.
        var reps: Int?
        var weight: Double?
        var seconds: Int?
        var targetMinKg: Double? = nil
        var targetMaxKg: Double? = nil
        var setNumber: Int
        var totalSets: Int
        var groupLabel: String?
        /// "superset" | "circuit" | nil (straight sets) — see `GroupKind` wire mapping below.
        var groupKind: String?
        var round: Int?
        var totalRounds: Int?
        var miniMap: [MiniMapItemState]?
        /// "pending" | "done" | "skipped" — see `SetState` wire mapping below.
        var state: String
        /// The frozen prescribed target, `nil` when this step was added live (no prescribed
        /// counterpart existed at session start).
        var prescribedReps: Int?
        var prescribedWeight: Double?
        var prescribedSeconds: Int?
        var prescribedTargetMinKg: Double? = nil
        var prescribedTargetMaxKg: Double? = nil
    }

    struct MiniMapItemState: Codable {
        var shortLabel: String
        var name: String
        var isCurrent: Bool
    }

    /// Mirrors `RestPageInfo` verbatim.
    struct RestPageState: Codable {
        var seconds: Int
        var afterRound: Int
        var totalRounds: Int
        var groupLabel: String
        var nextUpName: String
    }

    /// Compact mirror of `CoachMessage` — `{kind, text, date}` only. `CoachMessage.id` is not
    /// preserved (it only matters for in-flight streaming/List identity, not for restored history),
    /// so a restored message gets a fresh id.
    struct CoachMessageState: Codable {
        var kind: String
        var text: String
        var date: Date
    }

    var steps: [StepState]
    var currentStepID: UUID?
    var rpe: [UUID: Double]
    /// Optional for backward-compatible decoding of active sessions saved before Tindeq support.
    var tindeqResults: [UUID: TindeqSetResult]?
    /// Optional for backward-compatible decoding of active sessions saved before Polar support.
    var heartRateSamples: [HeartRateSample]?
    var heartRateSensorName: String?
    var startedAt: Date
    var activePlanID: UUID?
    /// Reserved for a future `PlanRevisionRecord` reference (domain-primitives.md §8's
    /// `ActiveSessionRecord.planRevisionID`) — not yet tracked by `WorkoutSession`, so always `nil`
    /// today. Kept as a field (rather than omitted) so a later slice can start populating it without
    /// another schema change.
    var activePlanRevisionID: UUID?
    /// Per-exercise transcript, keyed the same way `WorkoutSession.transcripts` is.
    var transcripts: [String: [CoachMessageState]]

    // MARK: - WorkoutSession -> SessionState

    static func from(_ session: WorkoutSession) -> SessionState {
        let prescribedByID: [WorkoutStep.ID: WorkoutStep] = Dictionary(
            uniqueKeysWithValues: session.prescribedSteps.map { ($0.id, $0) }
        )

        let steps: [StepState] = session.steps.map { step in
            let prescribedInfo: SetPageInfo? = {
                guard case .set(let info)? = prescribedByID[step.id]?.page else { return nil }
                return info
            }()

            let page: PageState
            switch step.page {
            case .set(let info):
                let actual = fields(from: info.exercise.target)
                let prescribed = prescribedInfo.map { fields(from: $0.exercise.target) }
                page = .set(SetPageState(
                    exerciseName: info.exercise.name,
                    exerciseCue: info.exercise.cue,
                    reps: actual.reps,
                    weight: actual.weight,
                    seconds: actual.seconds,
                    targetMinKg: actual.targetMinKg,
                    targetMaxKg: actual.targetMaxKg,
                    setNumber: info.setNumber,
                    totalSets: info.totalSets,
                    groupLabel: info.groupLabel,
                    groupKind: wireKey(from: info.groupKind),
                    round: info.round,
                    totalRounds: info.totalRounds,
                    miniMap: info.miniMap?.map { MiniMapItemState(shortLabel: $0.shortLabel, name: $0.name, isCurrent: $0.isCurrent) },
                    state: wireKey(from: info.state),
                    prescribedReps: prescribed?.reps,
                    prescribedWeight: prescribed?.weight,
                    prescribedSeconds: prescribed?.seconds,
                    prescribedTargetMinKg: prescribed?.targetMinKg,
                    prescribedTargetMaxKg: prescribed?.targetMaxKg
                ))
            case .rest(let info):
                page = .rest(RestPageState(
                    seconds: info.seconds, afterRound: info.afterRound, totalRounds: info.totalRounds,
                    groupLabel: info.groupLabel, nextUpName: info.nextUpName
                ))
            }

            return StepState(
                id: step.id, blockIndex: step.blockIndex, blockName: step.blockName,
                moodKey: step.moodKey.wireKey, exerciseName: step.exerciseName, page: page
            )
        }

        let transcripts: [String: [CoachMessageState]] = session.transcripts.mapValues { messages in
            messages.map { CoachMessageState(kind: wireKey(from: $0.kind), text: $0.text, date: $0.date) }
        }

        return SessionState(
            steps: steps,
            currentStepID: session.currentStepID,
            rpe: session.rpe,
            tindeqResults: session.tindeqResults,
            heartRateSamples: session.heartRateSamples,
            heartRateSensorName: session.heartRateSensorName,
            startedAt: session.startedAt,
            activePlanID: session.activePlan?.id,
            activePlanRevisionID: nil,
            transcripts: transcripts
        )
    }

    // MARK: - Field <-> wire mapping (private, this file only)

    fileprivate static func fields(
        from target: SetTarget
    ) -> (reps: Int?, weight: Double?, seconds: Int?, targetMinKg: Double?, targetMaxKg: Double?) {
        switch target {
        case .reps(let count, let weight): return (count, weight, nil, nil, nil)
        case .timed(let seconds): return (nil, nil, seconds, nil, nil)
        case .tindeq(let seconds, let targetMinKg, let targetMaxKg):
            return (nil, nil, seconds, targetMinKg, targetMaxKg)
        }
    }

    fileprivate static func target(
        reps: Int?, weight: Double?, seconds: Int?, targetMinKg: Double?, targetMaxKg: Double?
    ) -> SetTarget {
        if let seconds, let targetMinKg, let targetMaxKg {
            return .tindeq(
                seconds: seconds, targetMinKg: targetMinKg, targetMaxKg: targetMaxKg)
        }
        if let seconds { return .timed(seconds: seconds) }
        return .reps(count: reps ?? 0, weight: weight)
    }

    fileprivate static func wireKey(from kind: GroupKind?) -> String? {
        switch kind {
        case .superset: return "superset"
        case .circuit: return "circuit"
        case nil: return nil
        }
    }

    fileprivate static func groupKind(from wireKey: String?) -> GroupKind? {
        switch wireKey {
        case "superset": return .superset
        case "circuit": return .circuit
        default: return nil
        }
    }

    fileprivate static func wireKey(from state: SetState) -> String {
        switch state {
        case .pending: return "pending"
        case .done: return "done"
        case .skipped: return "skipped"
        }
    }

    fileprivate static func setState(from wireKey: String) -> SetState {
        switch wireKey {
        case "done": return .done
        case "skipped": return .skipped
        default: return .pending
        }
    }

    fileprivate static func wireKey(from kind: CoachMessage.Kind) -> String {
        switch kind {
        case .coach: return "coach"
        case .user: return "user"
        case .diff: return "diff"
        }
    }

    fileprivate static func messageKind(from wireKey: String) -> CoachMessage.Kind {
        switch wireKey {
        case "user": return .user
        case "diff": return .diff
        default: return .coach
        }
    }
}

// MARK: - MoodKey wire mapping

extension MoodKey {
    /// `MoodKey` has no associated values, so a plain case-name string round-trips it losslessly
    /// without adding `Codable`/`RawRepresentable` conformance to the type itself in `Models.swift`.
    var wireKey: String {
        switch self {
        case .bench: return "bench"
        case .inclinePress: return "inclinePress"
        case .row: return "row"
        case .facePull: return "facePull"
        case .cableFly: return "cableFly"
        case .plank: return "plank"
        case .rest: return "rest"
        }
    }

    init(wireKey: String) {
        switch wireKey {
        case "bench": self = .bench
        case "inclinePress": self = .inclinePress
        case "row": self = .row
        case "facePull": self = .facePull
        case "cableFly": self = .cableFly
        case "plank": self = .plank
        default: self = .rest
        }
    }
}

// MARK: - SessionState -> WorkoutSession

extension WorkoutSession {
    /// Rebuilds a live `WorkoutSession` from a durable `SessionState` snapshot — the counterpart to
    /// `SessionState.from(_:)`, and the only way `ActiveSessionStore.loadSession` reconstructs a
    /// resumed workout. Deliberately does NOT re-read `activePlanID`'s `PlanRecord` for anything
    /// beyond re-attaching the `activePlan` reference (best-effort — the plan may have changed or
    /// been deleted since the snapshot was taken; every step's own prescribed/actual values already
    /// came from `state`, not from the plan).
    static func restore(from state: SessionState, modelContext: ModelContext?) -> WorkoutSession {
        var steps: [WorkoutStep] = []
        var prescribedSteps: [WorkoutStep] = []
        steps.reserveCapacity(state.steps.count)

        for stepState in state.steps {
            let moodKey = MoodKey(wireKey: stepState.moodKey)

            switch stepState.page {
            case .set(let setState):
                let target = SessionState.target(
                    reps: setState.reps, weight: setState.weight, seconds: setState.seconds,
                    targetMinKg: setState.targetMinKg, targetMaxKg: setState.targetMaxKg)
                let exercise = Exercise(name: setState.exerciseName, cue: setState.exerciseCue, target: target, moodKey: moodKey)
                let info = SetPageInfo(
                    exercise: exercise,
                    setNumber: setState.setNumber,
                    totalSets: setState.totalSets,
                    groupLabel: setState.groupLabel,
                    groupKind: SessionState.groupKind(from: setState.groupKind),
                    round: setState.round,
                    totalRounds: setState.totalRounds,
                    miniMap: setState.miniMap?.map { MiniMapItem(shortLabel: $0.shortLabel, name: $0.name, isCurrent: $0.isCurrent) },
                    state: SessionState.setState(from: setState.state)
                )
                steps.append(WorkoutStep(
                    id: stepState.id, blockIndex: stepState.blockIndex, blockName: stepState.blockName,
                    moodKey: moodKey, page: .set(info), exerciseName: stepState.exerciseName
                ))

                let hasPrescribed = setState.prescribedReps != nil
                    || setState.prescribedWeight != nil
                    || setState.prescribedSeconds != nil
                    || setState.prescribedTargetMinKg != nil
                    || setState.prescribedTargetMaxKg != nil
                if hasPrescribed {
                    let prescribedTarget = SessionState.target(
                        reps: setState.prescribedReps, weight: setState.prescribedWeight,
                        seconds: setState.prescribedSeconds,
                        targetMinKg: setState.prescribedTargetMinKg,
                        targetMaxKg: setState.prescribedTargetMaxKg
                    )
                    var prescribedInfo = info
                    prescribedInfo.exercise.target = prescribedTarget
                    prescribedInfo.state = .pending
                    prescribedSteps.append(WorkoutStep(
                        id: stepState.id, blockIndex: stepState.blockIndex, blockName: stepState.blockName,
                        moodKey: moodKey, page: .set(prescribedInfo), exerciseName: stepState.exerciseName
                    ))
                }

            case .rest(let restState):
                let info = RestPageInfo(
                    seconds: restState.seconds, afterRound: restState.afterRound, totalRounds: restState.totalRounds,
                    groupLabel: restState.groupLabel, nextUpName: restState.nextUpName
                )
                steps.append(WorkoutStep(
                    id: stepState.id, blockIndex: stepState.blockIndex, blockName: stepState.blockName,
                    moodKey: moodKey, page: .rest(info), exerciseName: stepState.exerciseName
                ))
            }
        }

        let transcripts: [String: [CoachMessage]] = state.transcripts.mapValues { messages in
            messages.map { CoachMessage(kind: SessionState.messageKind(from: $0.kind), text: $0.text, date: $0.date) }
        }

        let activePlan: PlanRecord? = {
            guard let modelContext, let planID = state.activePlanID else { return nil }
            var descriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.id == planID })
            descriptor.fetchLimit = 1
            return try? modelContext.fetch(descriptor).first
        }()

        return WorkoutSession(
            steps: steps,
            prescribedSteps: prescribedSteps,
            currentStepID: state.currentStepID,
            startedAt: state.startedAt,
            rpe: state.rpe,
            tindeqResults: state.tindeqResults ?? [:],
            heartRateSamples: state.heartRateSamples ?? [],
            heartRateSensorName: state.heartRateSensorName,
            transcripts: transcripts,
            activePlan: activePlan,
            modelContext: modelContext
        )
    }
}
