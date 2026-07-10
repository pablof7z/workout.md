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
    /// Nil for a straight-sets block; `.superset` or `.circuit` inside a group. Carried through so
    /// history persistence can record the block's organization without guessing from the label text.
    let groupKind: GroupKind?
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
    /// The in-flight streaming coach-reply message id per exercise, while a `send_message` turn is
    /// being streamed — see `beginStreamingReply`/`replaceStreamingText`/`finalizeStreamingReply`.
    private var streamingMessageID: [String: UUID] = [:]

    /// A snapshot of `steps` as they stood at session start, before any coach edit or reps-stepper
    /// nudge mutated a target in place. `WorkoutStep`/`SetPageInfo`/`Exercise` are all value types, so
    /// this copy is fully independent of `steps` and stays the "prescribed" record for history —
    /// while `steps` (mutated live) stands in for "actual" once the session finishes.
    let startedAt: Date = .now
    let prescribedSteps: [WorkoutStep]

    /// The persisted plan this session was started from — the same `PlanRecord` the coach's
    /// `edit_plan` tool mutates (see `applyEditPlan` below), so a structural change lands both in
    /// the durable plan (future sessions) and, best-effort, in this session's own live `steps`.
    /// `nil` only for a session built directly from raw `steps` (e.g. previews/tests).
    var activePlan: PlanRecord?
    /// Needed to persist `activePlan` mutations `edit_plan` makes. Not used for anything else —
    /// completed-session history is still saved by the app root via `makeRecord`, not from here.
    var modelContext: ModelContext?

    init(steps: [WorkoutStep] = [], activePlan: PlanRecord? = nil, modelContext: ModelContext? = nil) {
        self.steps = steps
        self.prescribedSteps = steps
        self.currentStepID = steps.first?.id
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
    /// `on_text_delta` chunk. Whole-value replacement rather than append: `CoachStreamSink` (see
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
    }

    // MARK: Live coach — grounding context for the model

    /// A terse, factual summary of `exercise`'s sets — prescribed vs. actual/RPE so far, and which
    /// remain upcoming — prefixed to every `user_message` sent to the coach engine. This is what
    /// makes `adjust_set`/`skip_set` (which address a set by a zero-based `set_index` within the
    /// exercise) meaningful: the model is told exactly which index is which set.
    func coachContext(for exercise: String) -> String {
        let indices = stepIndices(forExercise: exercise)
        guard !indices.isEmpty else { return "Exercise: \(exercise) (not part of today's plan)." }

        var lines = ["Exercise: \(exercise)"]
        for (setIndex, stepIdx) in indices.enumerated() {
            guard case .set(let info) = steps[stepIdx].page else { continue }
            let prescribed = prescribedDisplay(atStepIndex: stepIdx)
            var line = "- set_index \(setIndex): prescribed \(prescribed)"
            if info.skipped {
                line += " — skipped"
            } else if let idx = currentIndex, stepIdx < idx {
                line += " — done: \(info.exercise.target.displayString)"
                if let r = rpe[steps[stepIdx].id] {
                    line += ", RPE \(String(format: "%.1f", r))"
                }
            } else if stepIdx == currentIndex {
                line += " — current set"
                if let r = rpe[steps[stepIdx].id] {
                    line += ", RPE \(String(format: "%.1f", r))"
                }
            } else {
                line += " — upcoming"
            }
            lines.append(line)
        }
        if deloaded.contains(exercise) {
            lines.append("Note: \(exercise) is already flagged for deload.")
        }
        return lines.joined(separator: "\n")
    }

    /// Indices into `steps` (== indices into `prescribedSteps`, the two arrays are parallel) for
    /// every set page belonging to `exercise`, in plan order — this is the space `set_index`
    /// addresses.
    private func stepIndices(forExercise name: String) -> [Int] {
        steps.indices.filter { idx in
            if case .set(let info) = steps[idx].page { return info.exercise.name == name }
            return false
        }
    }

    private func prescribedDisplay(atStepIndex idx: Int) -> String {
        guard idx < prescribedSteps.count, case .set(let info) = prescribedSteps[idx].page else { return "—" }
        return info.exercise.target.displayString
    }

    // MARK: Live coach — tool application (CoachHost side effects)

    /// Dispatches one coach tool call (routed here from `CoachHost.applyTool` in `CoachController`)
    /// by name, decoding `argsJson` into the shape `core/workout-core/src/coach/tools.rs` defines,
    /// mutating `steps` (so the runner's upcoming pages reflect it immediately), appending the
    /// applied-diff transcript line, and returning a terse confirmation the model sees as the tool's
    /// result. `transcriptExercise` is the exercise the Coach screen is currently scoped to — the
    /// diff line is always shown there, even if the tool targets a different named exercise.
    func applyCoachTool(name: String, argsJson: String, transcriptExercise: String) -> String {
        let data = Data(argsJson.utf8)
        let decoder = JSONDecoder()

        switch name {
        case "adjust_set":
            struct Args: Decodable { let exercise: String; let set_index: Int; let new_weight: Double?; let new_reps: Int? }
            guard let args = try? decoder.decode(Args.self, from: data) else {
                return malformed(name, transcriptExercise)
            }
            return applyAdjustSet(
                exercise: args.exercise, setIndex: args.set_index,
                newWeight: args.new_weight, newReps: args.new_reps,
                transcriptExercise: transcriptExercise
            )

        case "skip_set":
            struct Args: Decodable { let exercise: String; let set_index: Int }
            guard let args = try? decoder.decode(Args.self, from: data) else {
                return malformed(name, transcriptExercise)
            }
            return applySkipSet(exercise: args.exercise, setIndex: args.set_index, transcriptExercise: transcriptExercise)

        case "deload_exercise":
            struct Args: Decodable { let exercise: String; let weeks: Int }
            guard let args = try? decoder.decode(Args.self, from: data) else {
                return malformed(name, transcriptExercise)
            }
            return applyDeloadExercise(exercise: args.exercise, weeks: args.weeks, transcriptExercise: transcriptExercise)

        case "add_note":
            struct Args: Decodable { let scope: String; let text: String }
            guard let args = try? decoder.decode(Args.self, from: data) else {
                return malformed(name, transcriptExercise)
            }
            return applyAddNote(scope: args.scope, text: args.text, transcriptExercise: transcriptExercise)

        case "edit_plan":
            struct Args: Decodable { let instruction: String }
            guard let args = try? decoder.decode(Args.self, from: data) else {
                return malformed(name, transcriptExercise)
            }
            return applyEditPlan(instruction: args.instruction, transcriptExercise: transcriptExercise)

        default:
            let message = "Unknown tool \(name)."
            append(CoachMessage(kind: .diff, text: message), to: transcriptExercise)
            return message
        }
    }

    private func malformed(_ tool: String, _ transcriptExercise: String) -> String {
        let message = "Could not parse arguments for \(tool)."
        append(CoachMessage(kind: .diff, text: message), to: transcriptExercise)
        return message
    }

    /// `adjust_set` — changes an upcoming (or the current) set's weight and/or rep target in place.
    private func applyAdjustSet(exercise: String, setIndex: Int, newWeight: Double?, newReps: Int?, transcriptExercise: String) -> String {
        let indices = stepIndices(forExercise: exercise)
        guard setIndex >= 0, setIndex < indices.count else {
            let message = "No set \(setIndex) found for \(exercise)."
            append(CoachMessage(kind: .diff, text: message), to: transcriptExercise)
            return message
        }
        let stepIdx = indices[setIndex]
        guard case .set(var info) = steps[stepIdx].page else {
            let message = "Could not adjust \(exercise) set \(setIndex)."
            append(CoachMessage(kind: .diff, text: message), to: transcriptExercise)
            return message
        }

        var changes: [String] = []
        switch info.exercise.target {
        case .reps(let count, let weight):
            let finalReps = newReps ?? count
            let finalWeight = newWeight ?? weight
            if let newWeight, newWeight != weight {
                changes.append(weight == nil ? "set \(Int(newWeight)) lb" : "\(Int(weight!)) → \(Int(newWeight)) lb")
            }
            if let newReps, newReps != count {
                changes.append("\(count) → \(newReps) reps")
            }
            info.exercise.target = .reps(count: finalReps, weight: finalWeight)
        case .timed(let seconds):
            // The tool schema is generic across rep- and time-based sets; a timed hold repurposes
            // `new_reps` as the new duration in seconds since there's no dedicated field for it.
            if let newReps, newReps != seconds {
                changes.append("\(seconds) → \(newReps) sec")
                info.exercise.target = .timed(seconds: newReps)
            }
        }
        steps[stepIdx].page = .set(info)

        let confirmation = changes.isEmpty
            ? "\(exercise) set \(setIndex + 1): no change (fields matched the current plan)."
            : "\(exercise) set \(setIndex + 1): \(changes.joined(separator: ", "))."
        append(CoachMessage(kind: .diff, text: confirmation), to: transcriptExercise)
        return confirmation
    }

    /// `skip_set` — marks a specific set skipped for the rest of the session.
    private func applySkipSet(exercise: String, setIndex: Int, transcriptExercise: String) -> String {
        let indices = stepIndices(forExercise: exercise)
        guard setIndex >= 0, setIndex < indices.count else {
            let message = "No set \(setIndex) found for \(exercise)."
            append(CoachMessage(kind: .diff, text: message), to: transcriptExercise)
            return message
        }
        let stepIdx = indices[setIndex]
        guard case .set(var info) = steps[stepIdx].page else {
            let message = "Could not skip \(exercise) set \(setIndex)."
            append(CoachMessage(kind: .diff, text: message), to: transcriptExercise)
            return message
        }
        info.skipped = true
        steps[stepIdx].page = .set(info)

        let confirmation = "\(exercise) set \(setIndex + 1): skipped."
        append(CoachMessage(kind: .diff, text: confirmation), to: transcriptExercise)
        return confirmation
    }

    /// `deload_exercise` — flags the exercise for a reduced-load block and records why.
    private func applyDeloadExercise(exercise: String, weeks: Int, transcriptExercise: String) -> String {
        deloaded.insert(exercise)
        offerDeload.remove(exercise)
        let confirmation = "\(exercise): deload scheduled for \(weeks) week\(weeks == 1 ? "" : "s")."
        append(CoachMessage(kind: .diff, text: confirmation), to: transcriptExercise)
        return confirmation
    }

    /// `add_note` — records a freestanding note; no set/plan mutation.
    private func applyAddNote(scope: String, text: String, transcriptExercise: String) -> String {
        let confirmation = "Note (\(scope)): \(text)"
        append(CoachMessage(kind: .diff, text: confirmation), to: transcriptExercise)
        return confirmation
    }

    /// `edit_plan` — structural plan changes (swap an exercise, add a drop set, trim/add volume for
    /// a body-part group) are real now: `PlanEditInterpreter` pattern-matches `instruction` and, when
    /// it recognizes one, mutates the ACTIVE `PlanRecord` (persisted — affects future sessions) and
    /// best-effort mirrors the same change onto this session's live `steps` (if one is running
    /// against that plan) without disturbing any set already completed. Falls back to recording the
    /// instruction as a plain plan note — same as this tool's original prototype behavior — when
    /// nothing matches, rather than silently no-op'ing.
    private func applyEditPlan(instruction: String, transcriptExercise: String) -> String {
        guard let activePlan else {
            let confirmation = "Plan note recorded: \(instruction)"
            append(CoachMessage(kind: .diff, text: confirmation), to: transcriptExercise)
            return confirmation
        }
        let applied = PlanEditInterpreter.applyToPlan(instruction: instruction, plan: activePlan)
        if applied.changed {
            try? modelContext?.save()
            PlanEditInterpreter.applyToSession(instruction: instruction, session: self)
        }
        append(CoachMessage(kind: .diff, text: applied.summary), to: transcriptExercise)
        return applied.summary
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

