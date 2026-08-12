import SwiftUI
import Observation
import SwiftData

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

/// What the athlete is meant to hit for a given set. A Tindeq hold is deliberately its own case:
/// duration and force corridor are plan data, not values inferred from an exercise name or cue.
enum SetTarget {
    case reps(count: Int, weight: Double?)
    case timed(seconds: Int)
    case tindeq(seconds: Int, targetMinKg: Double, targetMaxKg: Double)

    var displayString: String {
        switch self {
        case .reps(let count, let weight):
            if let weight {
                return "\(count) reps · \(Int(weight)) lb"
            }
            return "\(count) reps"
        case .timed(let seconds):
            return "\(seconds) sec"
        case .tindeq(let seconds, let targetMinKg, let targetMaxKg):
            return "\(seconds) sec · \(Self.kilograms(targetMinKg))–\(Self.kilograms(targetMaxKg)) kg"
        }
    }

    var isTimed: Bool {
        switch self {
        case .timed, .tindeq: return true
        case .reps: return false
        }
    }

    var isTindeq: Bool {
        if case .tindeq = self { return true }
        return false
    }

    var weight: Double? {
        if case .reps(_, let weight) = self { return weight }
        return nil
    }

    private static func kilograms(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// The compact, durable result of one measured Tindeq hold. Raw 80 Hz samples stay ephemeral;
/// history keeps the useful training facts and the runner keeps only a short display trace.
struct TindeqSetResult: Codable, Equatable, Sendable {
    var peakKg: Double
    var averageKg: Double
    var holdSeconds: Double
    var timeInTargetSeconds: Double
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
enum MoodKey: CaseIterable {
    case bench, inclinePress, row, facePull, cableFly, plank, rest

    /// Non-`.rest` cases, in a fixed rotation order — used to assign a varied background story to
    /// exercises that come from a user-authored `PlanRecord` (which has no hand-picked `MoodKey` of
    /// its own), by cycling through this list positionally.
    private static let rotation: [MoodKey] = [.bench, .inclinePress, .row, .facePull, .cableFly, .plank]

    static func atIndex(_ index: Int) -> MoodKey {
        rotation[((index % rotation.count) + rotation.count) % rotation.count]
    }
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
    let id: UUID
    let blockIndex: Int
    let blockName: String
    let moodKey: MoodKey
    var page: StepPage
    var exerciseName: String?

    /// `id` defaults to a fresh `UUID()` — every ordinary call site (`PlanConversion.toWorkoutSteps`,
    /// `WorkoutSession.addSet`, ...) keeps constructing a brand-new step exactly as before. The
    /// explicit `id:` parameter exists so `WorkoutSession.restore(from:modelContext:)`
    /// (`Session/SessionState.swift`) can rebuild a resumed step with the SAME id it had before the
    /// app was terminated — it's what `SetRecord.sourceStepID`, `WorkoutSession.rpe`,
    /// `currentStepID`, and the running pager's SwiftUI list identity all key off. Written out by
    /// hand (rather than relying on the compiler-synthesized memberwise initializer) because a
    /// stored property with an inline default value (the old `let id = UUID()`) can't be overridden
    /// by any initializer, synthesized or custom — it re-evaluates its own default unconditionally.
    init(id: UUID = UUID(), blockIndex: Int, blockName: String, moodKey: MoodKey, page: StepPage, exerciseName: String?) {
        self.id = id
        self.blockIndex = blockIndex
        self.blockName = blockName
        self.moodKey = moodKey
        self.page = page
        self.exerciseName = exerciseName
    }
}

enum StepPage {
    case set(SetPageInfo)
    case rest(RestPageInfo)
}

/// A set's status, rendered persistently by that set's own slider (see `DoneSkipThumb` in
/// `StepPageView.swift`) — every set carries its own independent `state`, regardless of which page
/// the pager happens to be showing. There is no "active" set anymore: any set, past or future, can
/// be sitting in any of these three states, and the athlete can slide it into any other at any time
/// (e.g. mark a set done, page away, come back, and change it to skipped, or just fix the weight).
enum SetState: Equatable {
    case pending
    case done
    case skipped
}

struct SetPageInfo {
    var exercise: Exercise
    let setNumber: Int
    let totalSets: Int
    let groupLabel: String?
    /// Nil for a straight-sets block; `.superset` or `.circuit` inside a group. Carried through so
    /// history persistence can record the block's organization without guessing from the label text.
    let groupKind: GroupKind?
    let round: Int?
    let totalRounds: Int?
    let miniMap: [MiniMapItem]?
    /// The one and only status this set carries. Persisted on `WorkoutSession.steps` (a value-type
    /// array), so it round-trips exactly like the rest of `SetPageInfo` and is what the runner's
    /// per-page slider both renders and mutates.
    var state: SetState = .pending

    /// Back-compat read-only views for history/persistence/list code that still reasons in booleans
    /// (`SetRecord.skipped`, `WorkoutListView`'s badge, etc.) — derived from `state`, never stored
    /// separately, so the two can't drift.
    var skipped: Bool { state == .skipped }
    var completed: Bool { state == .done }
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
    let id: UUID
    let kind: Kind
    /// `var` (not `let`) so a streaming coach reply can be mutated in place by identity as
    /// `on_text_delta` chunks arrive, rather than the transcript array replacing the whole message.
    var text: String
    /// When the line was sent, so a full-session transcript (spanning many exercises) can be
    /// reassembled in chronological order when snapshotted to history.
    let date: Date

    init(kind: Kind, text: String, id: UUID = UUID(), date: Date = .now) {
        self.id = id
        self.kind = kind
        self.text = text
        self.date = date
    }
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

/// One live reading received from a Polar monitor during the active workout.
struct HeartRateSample: Codable, Equatable {
    let timestamp: Date
    let beatsPerMinute: Int
}

// MARK: - Shared Observable Session

/// The single source of truth for a live workout. The runner, the effort control, the reps stepper,
/// and the coach all read and mutate this one object (injected via `.environment`), so an edit made
/// anywhere reflects everywhere — including the runner's upcoming pages.
@Observable
final class WorkoutSession {
    var steps: [WorkoutStep]
    /// The ONE pointer: whichever page the native paging `ScrollView` is currently showing, bound via
    /// `.scrollPosition(id:)` in `RunnerView`. Navigation is completely free — there is no separate
    /// "active" set that gates it — so scrolling anywhere just moves this. Each set's done/skipped/
    /// pending status lives independently on that set's own `SetPageInfo.state` (see `setState(_:for:)`
    /// below), not on this pointer, which is why paging away and back never loses or "un-logs"
    /// anything.
    var currentStepID: WorkoutStep.ID?
    /// Committed effort per set, as RPE 6–10.
    var rpe: [WorkoutStep.ID: Double] = [:]
    /// Measured result per Tindeq-assisted set.
    var tindeqResults: [WorkoutStep.ID: TindeqSetResult] = [:]
    /// Raw Polar readings captured during this workout. Empty when no monitor was available.
    var heartRateSamples: [HeartRateSample] = []
    /// Bluetooth display name of the Polar that supplied `heartRateSamples`.
    var heartRateSensorName: String?
    /// Coach transcript per exercise name.
    var transcripts: [String: [CoachMessage]] = [:]
    /// Exercises the coach has offered a "Deload 2 weeks" follow-up for.
    var offerDeload: Set<String> = []
    /// Exercises marked to deload / skip upcoming sessions.
    var deloaded: Set<String> = []
    /// The in-flight streaming coach-reply message id per exercise, while a `send_message` turn is
    /// being streamed — see `beginStreamingReply`/`replaceStreamingText`/`finalizeStreamingReply`.
    private var streamingMessageID: [String: UUID] = [:]

    /// A snapshot of `steps` as they stood at session start, before any coach edit or reps-stepper
    /// nudge mutated a target in place. `WorkoutStep`/`SetPageInfo`/`Exercise` are all value types, so
    /// this copy is fully independent of `steps` and stays the "prescribed" record for history —
    /// while `steps` (mutated live) stands in for "actual" once the session finishes. Joined to
    /// `steps` by stable `WorkoutStep.id`, never by position — see `makeRecord` (PersistenceModels.swift)
    /// and `WorkoutSession.restore(from:modelContext:)` below.
    let startedAt: Date
    let prescribedSteps: [WorkoutStep]

    /// Fired after any mutation the durable active-session snapshot should reflect — wired by
    /// `RootView` to a debounced `ActiveSessionStore.save` call (domain-primitives.md §8: the
    /// in-progress workout is persisted continuously, not just at Done, so a crash/force-quit mid-
    /// workout can be resumed). `nil` for sessions built outside the running app (tests, previews),
    /// where it's simply never called.
    var onChange: (() -> Void)?

    /// The persisted plan this session was started from — `plan_apply` (`AppCoachHost`) mutates the
    /// same `PlanRecord` via `PlanRepository`, independent of this session; `session_apply` is what
    /// mirrors a live-workout change onto this session's own `steps`. `nil` only for a session built
    /// directly from raw `steps` (e.g. previews/tests).
    var activePlan: PlanRecord?
    /// Not read by `WorkoutSession` itself anymore (`plan_apply`/`session_apply` route through
    /// `AppCoachHost`'s own `modelContext`) — kept for call sites that still construct a session
    /// with one and completed-session history, which is still saved by the app root via
    /// `makeRecord`, not from here.
    var modelContext: ModelContext?

    init(steps: [WorkoutStep] = [], activePlan: PlanRecord? = nil, modelContext: ModelContext? = nil) {
        self.steps = steps
        self.prescribedSteps = steps
        self.currentStepID = steps.first?.id
        self.startedAt = .now
        self.activePlan = activePlan
        self.modelContext = modelContext
    }

    /// Rebuilds a session with an explicit, independent `prescribedSteps` array, a preserved
    /// `currentStepID`/`startedAt`/`rpe`/`transcripts`, and PRESERVED step ids — used only by
    /// `WorkoutSession.restore(from:modelContext:)` (`Session/SessionState.swift`), where `steps`
    /// (the live/actual array) may already differ structurally from `prescribedSteps` (frozen at the
    /// original session start) because of coach edits made before the app was terminated. Ordinary
    /// session start goes through the convenience initializer above instead, where the two arrays
    /// start out identical.
    init(
        steps: [WorkoutStep],
        prescribedSteps: [WorkoutStep],
        currentStepID: WorkoutStep.ID?,
        startedAt: Date,
        rpe: [WorkoutStep.ID: Double] = [:],
        tindeqResults: [WorkoutStep.ID: TindeqSetResult] = [:],
        heartRateSamples: [HeartRateSample] = [],
        heartRateSensorName: String? = nil,
        transcripts: [String: [CoachMessage]] = [:],
        activePlan: PlanRecord? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.steps = steps
        self.prescribedSteps = prescribedSteps
        self.currentStepID = currentStepID
        self.startedAt = startedAt
        self.rpe = rpe
        self.tindeqResults = tindeqResults
        self.heartRateSamples = heartRateSamples
        self.heartRateSensorName = heartRateSensorName
        self.transcripts = transcripts
        self.activePlan = activePlan
        self.modelContext = modelContext
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

    /// The exercise the coach is scoped to: whatever's currently on screen (navigation is free now,
    /// so "current" just means "wherever the pager is"), or for a rest page the next-up movement.
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
        onChange?()
    }

    func setTindeqResult(_ result: TindeqSetResult, for id: WorkoutStep.ID) {
        tindeqResults[id] = result
        onChange?()
    }

    func clearTindeqResult(for id: WorkoutStep.ID) {
        tindeqResults.removeValue(forKey: id)
        onChange?()
    }

    func recordHeartRate(_ sample: HeartRateSample, sensorName: String) {
        heartRateSensorName = sensorName
        heartRateSamples.append(sample)
        onChange?()
    }

    // MARK: Reps/weight floating-row edits
    //
    // Mirrors of `setTarget` (the coach's `session_apply` tool, below) for the runner's
    // always-visible reps/weight rows on the set page — the same mutation path, driven by direct
    // − / + taps instead of a coach tool call. Both mutate `steps` in place so the change is live
    // in the runner AND becomes the "actual" logged value once the session finishes (see
    // `prescribedSteps` above).

    func adjustReps(forStepID id: WorkoutStep.ID, delta: Int) {
        guard let idx = steps.firstIndex(where: { $0.id == id }),
              case .set(var info) = steps[idx].page,
              case .reps(let count, let weight) = info.exercise.target else { return }
        let newCount = max(0, count + delta)
        info.exercise.target = .reps(count: newCount, weight: weight)
        steps[idx].page = .set(info)
        onChange?()
    }

    /// Adjusts the current step's weight by `delta` (e.g. ±5 lb), floored at 0. No-ops for steps
    /// that don't carry a weight (bodyweight movements, timed holds).
    func adjustWeight(forStepID id: WorkoutStep.ID, delta: Double) {
        guard let idx = steps.firstIndex(where: { $0.id == id }),
              case .set(var info) = steps[idx].page,
              case .reps(let count, let weight) = info.exercise.target,
              let weight else { return }
        let newWeight = max(0, weight + delta)
        info.exercise.target = .reps(count: count, weight: newWeight)
        steps[idx].page = .set(info)
        onChange?()
    }

    // MARK: Done / Skip (the runner's per-set thumb — always targets the set it lives on, whatever
    // that set's current state, not some separate "active" pointer)

    /// Sets `id`'s status directly. This is the ONLY mutation the runner's thumb performs, and it
    /// works identically for every set — past, current, or future, already-logged or not. Sliding a
    /// done set back to skipped, or a skipped set back to pending, or a long-past set's weight fixed
    /// after the fact are all just this same call with a different `id`/`newState` pair.
    func setState(_ newState: SetState, for id: WorkoutStep.ID) {
        guard let idx = steps.firstIndex(where: { $0.id == id }),
              case .set(var info) = steps[idx].page else { return }
        info.state = newState
        steps[idx].page = .set(info)
        onChange?()
    }

    /// The step immediately after `id` in `steps`, if any — the auto-advance target once a set
    /// commits to `.done`/`.skipped` (see `advanceToNextStep(after:)` below).
    func nextStepID(after id: WorkoutStep.ID) -> WorkoutStep.ID? {
        guard let idx = steps.firstIndex(where: { $0.id == id }), idx + 1 < steps.count else { return nil }
        return steps[idx + 1].id
    }

    /// Animates the native paging `ScrollView` (via its `.scrollPosition(id: $session.currentStepID)`
    /// binding in `RunnerView`) to the set right after `id`, called once that set commits to
    /// `.done`/`.skipped` — either by sliding `DoneSkipThumb` or by picking an effort value in the
    /// tap-to-open prompt (see `StepPageView.SetGestureLayer`). A no-op past the last step. This
    /// never fights the pager: it just moves the same `currentStepID` a normal swipe would, so the
    /// user can always swipe back to re-edit any set afterward.
    func advanceToNextStep(after id: WorkoutStep.ID) {
        guard let next = nextStepID(after: id) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            currentStepID = next
        }
    }

    // MARK: Live coach — streaming transcript

    /// Appends the athlete's own message to `exercise`'s transcript. Public entry point for
    /// `CoachController`, which owns turn orchestration but leaves all transcript/session state in
    /// `WorkoutSession`.
    func appendUserMessage(_ text: String, to exercise: String) {
        append(CoachMessage(kind: .user, text: text), to: exercise)
    }

    /// Opens an empty coach-reply placeholder that `replaceStreamingText`/`finalizeStreamingReply`
    /// fill in as the turn streams — the visible "live typing" effect in `CoachView`.
    func beginStreamingReply(for exercise: String) {
        let placeholder = CoachMessage(kind: .coach, text: "")
        append(placeholder, to: exercise)
        streamingMessageID[exercise] = placeholder.id
    }

    /// Overwrites the in-flight placeholder for `exercise` with `text` wholesale, called after every
    /// `on_text_delta` chunk. Whole-value replacement rather than append: `CoachConverseSink` (see
    /// `CoachController.swift`) runs each raw delta through `ThinkStripper`, whose think-stripped
    /// "visible" projection of a growing raw buffer can *shrink* — not just grow — mid-stream (a
    /// model that omits the opening `<think>` tag makes everything before the eventual `</think>`
    /// retroactively hidden once that close tag arrives), which a plain `+=` can't express.
    func replaceStreamingText(_ text: String, for exercise: String) {
        guard let id = streamingMessageID[exercise],
              var list = transcripts[exercise],
              let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].text = text
        transcripts[exercise] = list
    }

    /// Resolves the in-flight placeholder with the turn's authoritative `on_completed` text (which
    /// should match the concatenated deltas, but is used verbatim rather than trusted-by-inference).
    /// A turn that only called tools (no closing prose) yields an empty `fullText` — that placeholder
    /// is dropped entirely rather than left as a blank line.
    func finalizeStreamingReply(for exercise: String, fullText: String) {
        defer { streamingMessageID[exercise] = nil }
        guard let id = streamingMessageID[exercise],
              var list = transcripts[exercise],
              let idx = list.firstIndex(where: { $0.id == id }) else {
            if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                append(CoachMessage(kind: .coach, text: fullText), to: exercise)
            }
            return
        }
        let resolved = fullText.isEmpty ? list[idx].text : fullText
        if resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list.remove(at: idx)
        } else {
            list[idx].text = resolved
        }
        transcripts[exercise] = list
        onChange?()
    }

    /// Resolves the in-flight placeholder as an error line instead (the turn's `on_error`).
    func finalizeStreamingReply(for exercise: String, replaceWithError message: String) {
        defer { streamingMessageID[exercise] = nil }
        if let id = streamingMessageID[exercise],
           var list = transcripts[exercise],
           let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].text = "Error: \(message)"
            transcripts[exercise] = list
        } else {
            append(CoachMessage(kind: .coach, text: "Error: \(message)"), to: exercise)
        }
        onChange?()
    }

    // MARK: Live coach — grounding context for the model

    private func prescribedDisplay(atStepIndex idx: Int) -> String {
        guard idx < prescribedSteps.count, case .set(let info) = prescribedSteps[idx].page else { return "—" }
        return info.exercise.target.displayString
    }

    /// A grounded listing of every set in the live session, one line per set, each carrying its own
    /// stable `WorkoutStep.id` — this is what lets `session_apply` (`AppCoachHost`) address a set
    /// precisely instead of by a fragile per-exercise index. Folded into `CoachContextAssembler`'s
    /// context on every turn while a workout is running (domain-primitives.md §6). Format:
    /// `- [id=<uuid>] Bench Press set 2/3: prescribed 135x10, state pending`.
    func sessionGrounding() -> String {
        var lines = ["Live workout — every set, addressable by [id=...] via session_apply:"]
        for (idx, step) in steps.enumerated() {
            guard case .set(let info) = step.page else { continue }
            let prescribed = prescribedDisplay(atStepIndex: idx)
            var line = "- [id=\(step.id.uuidString)] \(info.exercise.name) set \(info.setNumber)/\(info.totalSets): prescribed \(prescribed)"
            switch info.state {
            case .pending:
                line += idx == currentIndex ? ", state current" : ", state pending"
            case .done:
                line += ", state done: \(info.exercise.target.displayString)"
                if let r = rpe[step.id] { line += ", RPE \(String(format: "%.1f", r))" }
            case .skipped:
                line += ", state skipped"
            }
            lines.append(line)
        }
        if !deloaded.isEmpty {
            lines.append("Deload-flagged: \(deloaded.sorted().joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Live coach — session_apply mutation (by stable step id)
    //
    // Driven by `AppCoachHost.sessionApply` (decoded `SessionOp`s), replacing the old exercise-name
    // + `set_index` addressing (`applyAdjustSet`/`applySkipSet`) with the stable `WorkoutStep.id`
    // every line of `sessionGrounding()` carries. Each method mutates `steps` in place (so the
    // runner's upcoming pages reflect it immediately) and returns a terse confirmation string —
    // callers are responsible for appending it to the transcript (`AppCoachHost`'s `onDiff`), the
    // same separation `PlanRepository`/`MemoryStore` already have from their own callers.

    /// Adjusts the set at `id`'s target in place: reps and/or weight for a rep-based set, or —
    /// mirroring the legacy `adjust_set` tool's schema — `reps` repurposed as the new duration in
    /// seconds for a timed hold (there's no dedicated seconds field in `session_apply`'s wire
    /// shape). `nil` leaves that field unchanged.
    @discardableResult
    func setTarget(reps: Int?, weight: Double?, forStepID id: WorkoutStep.ID) -> String {
        guard let idx = steps.firstIndex(where: { $0.id == id }), case .set(var info) = steps[idx].page else {
            return "No such set."
        }
        var changes: [String] = []
        switch info.exercise.target {
        case .reps(let count, let currentWeight):
            let finalReps = reps ?? count
            let finalWeight = weight ?? currentWeight
            if let weight, weight != currentWeight {
                changes.append(currentWeight == nil ? "set \(Int(weight)) lb" : "\(Int(currentWeight!)) → \(Int(weight)) lb")
            }
            if let reps, reps != count {
                changes.append("\(count) → \(reps) reps")
            }
            info.exercise.target = .reps(count: finalReps, weight: finalWeight)
        case .timed(let seconds):
            if let reps, reps != seconds {
                changes.append("\(seconds) → \(reps) sec")
                info.exercise.target = .timed(seconds: reps)
            }
        case .tindeq(let seconds, let targetMinKg, let targetMaxKg):
            if let reps, reps != seconds {
                changes.append("\(seconds) → \(reps) sec")
                info.exercise.target = .tindeq(
                    seconds: reps, targetMinKg: targetMinKg, targetMaxKg: targetMaxKg)
            }
        }
        steps[idx].page = .set(info)
        onChange?()

        let label = "\(info.exercise.name) set \(info.setNumber)"
        return changes.isEmpty ? "\(label): no change (fields matched the current plan)." : "\(label): \(changes.joined(separator: ", "))."
    }

    /// Marks the set at `id` skipped for the rest of the session.
    @discardableResult
    func skip(forStepID id: WorkoutStep.ID) -> String {
        guard let idx = steps.firstIndex(where: { $0.id == id }), case .set(var info) = steps[idx].page else {
            return "No such set."
        }
        info.state = .skipped
        steps[idx].page = .set(info)
        onChange?()
        return "\(info.exercise.name) set \(info.setNumber): skipped."
    }

    /// Renames every not-yet-logged (`.pending`) step whose exercise is `exerciseName` to `newName`
    /// — addressed by exercise name (not a single step id) since a substitution applies to every
    /// remaining set of that movement. Already-`.done`/`.skipped` sets are left untouched so
    /// completed history stays factual (domain-primitives.md §8's "structural live edit preserves
    /// history" invariant).
    @discardableResult
    func substitute(exerciseName: String, newName: String) -> String {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "No replacement name given." }

        var changed = 0
        for idx in steps.indices {
            guard case .set(var info) = steps[idx].page,
                  info.exercise.name == exerciseName, info.state == .pending else { continue }
            info.exercise = Exercise(name: trimmedName, cue: info.exercise.cue, target: info.exercise.target, moodKey: info.exercise.moodKey)
            steps[idx].page = .set(info)
            steps[idx].exerciseName = trimmedName
            changed += 1
        }
        guard changed > 0 else { return "No upcoming sets found for \(exerciseName)." }
        onChange?()
        return "\(exerciseName) → \(trimmedName) for \(changed) upcoming set\(changed == 1 ? "" : "s")."
    }

    /// Inserts a new pending set immediately after `id`, cloning that set's exercise/block/group
    /// context — `reps`/`weight` default to the anchor set's own target when omitted. Mirrors the
    /// old `PlanEditInterpreter`'s drop-set insertion, generalized to any anchor set.
    @discardableResult
    func addSet(afterStepID id: WorkoutStep.ID, reps: Int?, weight: Double?) -> String {
        guard let idx = steps.firstIndex(where: { $0.id == id }), case .set(let info) = steps[idx].page else {
            return "No such set."
        }
        let newTarget: SetTarget
        switch info.exercise.target {
        case .reps(let count, let currentWeight):
            newTarget = .reps(count: reps ?? count, weight: weight ?? currentWeight)
        case .timed(let seconds):
            newTarget = .timed(seconds: reps ?? seconds)
        case .tindeq(let seconds, let targetMinKg, let targetMaxKg):
            newTarget = .tindeq(
                seconds: reps ?? seconds, targetMinKg: targetMinKg, targetMaxKg: targetMaxKg)
        }
        let newExercise = Exercise(name: info.exercise.name, cue: info.exercise.cue, target: newTarget, moodKey: info.exercise.moodKey)
        let newInfo = SetPageInfo(
            exercise: newExercise,
            setNumber: info.setNumber + 1,
            totalSets: info.totalSets + 1,
            groupLabel: info.groupLabel,
            groupKind: info.groupKind,
            round: info.round,
            totalRounds: info.totalRounds,
            miniMap: info.miniMap
        )
        let step = WorkoutStep(
            blockIndex: steps[idx].blockIndex, blockName: steps[idx].blockName,
            moodKey: info.exercise.moodKey, page: .set(newInfo), exerciseName: info.exercise.name
        )
        steps.insert(step, at: idx + 1)
        onChange?()
        return "Added a set for \(info.exercise.name)."
    }

    // MARK: Manual deload shortcut (Coach screen's "Deload 2 weeks" chip)

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
        onChange?()
    }

    // MARK: Summary

    func buildSummary() -> SessionSummary {
        let setSteps = steps.filter {
            if case .set = $0.page { return true }
            return false
        }
        // `state == .done` (set by sliding a set's thumb right) is the authoritative "actually
        // logged" signal, independent of where the pager happens to be sitting.
        let logged = setSteps.filter {
            if case .set(let info) = $0.page { return info.state == .done }
            return false
        }.count
        let values = setSteps.compactMap { rpe[$0.id] }
        let average: Double? = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        return SessionSummary(totalSets: setSteps.count, loggedSets: logged, averageRPE: average)
    }
}
