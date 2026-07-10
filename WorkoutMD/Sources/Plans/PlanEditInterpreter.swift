import Foundation

/// Best-effort, deterministic interpreter for the coach's `edit_plan` free-text `instruction` —
/// structural changes the model asks for in prose (swap an exercise, add a drop set, trim/add
/// volume for a body-part group) rather than through the single-set `adjust_set`/`skip_set` tools.
///
/// This deliberately does NOT make a second LLM round-trip from inside the tool call:
/// `CoachHost.applyTool` (see `WorkoutSessionCoachHost` in `CoachController.swift`) must return its
/// confirmation string *synchronously* to satisfy the UniFFI callback contract, and that call is
/// already reached via `DispatchQueue.main.sync` from the coach engine's own background tokio
/// runtime — a nested `CoachEngine.sendMessage` there would need its own completion to hop back onto
/// the main thread (`DispatchQueue.main.async`, see `CoachStreamSink`), which can't run while the
/// main thread sits blocked in that same `sync` call. A pattern-matched, local interpreter is the
/// simpler, robust path the product spec explicitly allows for `edit_plan`.
enum PlanEditInterpreter {
    struct Applied {
        let summary: String
        let changed: Bool
    }

    private enum VolumeDirection { case reduce, increase }

    /// Heuristic body-part → keyword groups. This prototype has no muscle-group tagging on
    /// exercises, so "reduce leg volume" is resolved by substring match against exercise names
    /// rather than real anatomy data.
    private static let bodyPartKeywords: [String: [String]] = [
        "leg": ["squat", "leg", "lunge", "deadlift", "calf", "hamstring", "quad"],
        "chest": ["bench", "press", "fly", "chest", "push"],
        "back": ["row", "pulldown", "pull-up", "pullup", "deadlift", "back"],
        "shoulder": ["shoulder", "overhead", "lateral", "face pull", "delt"],
        "arm": ["curl", "tricep", "bicep", "extension"]
    ]

    // MARK: - Apply to the persisted plan (always — this is the durable, future-sessions change)

    /// Mutates `plan` in place per `instruction` if a recognized pattern matches. Returns whether
    /// anything actually changed and a terse, human-readable summary — used both as the coach
    /// transcript's applied-diff line and, when nothing matched, as the honest fallback this tool
    /// always had: recording the instruction as a plain plan note rather than silently no-op'ing.
    static func applyToPlan(instruction: String, plan: PlanRecord) -> Applied {
        let lower = instruction.lowercased()

        if let (from, to) = parseSwap(lower) {
            if let exercise = findExercise(named: from, in: plan.allExercises) {
                let oldName = exercise.name
                exercise.name = to.capitalizingFirstLetterOfEachWord()
                return Applied(summary: "Swapped \(oldName) → \(exercise.name) in \(plan.name).", changed: true)
            }
        }

        if lower.contains("drop set"), let exercise = matchSingleExercise(lower, in: plan.allExercises) {
            addDropSet(to: exercise)
            return Applied(summary: "Added a drop set to \(exercise.name).", changed: true)
        }

        if let direction = volumeDirection(lower) {
            let matched = matchingExercises(lower, in: plan.allExercises)
            if !matched.isEmpty {
                for exercise in matched { adjustVolume(exercise, direction: direction) }
                let names = matched.map(\.name).joined(separator: ", ")
                let verb = direction == .reduce ? "Reduced" : "Increased"
                return Applied(summary: "\(verb) volume for \(names).", changed: true)
            }
        }

        return Applied(summary: "Plan note recorded: \(instruction)", changed: false)
    }

    // MARK: - Mirror onto the live, in-session steps (best-effort)

    /// Mirrors the same instruction onto a running `WorkoutSession`'s live `steps`, so a session in
    /// progress reflects the change immediately. Never re-identifies (removes/replaces by index) a
    /// step that's already been reached — only appends new steps or renames an exercise in place —
    /// so `rpe`/`deloaded` bookkeeping (keyed by `WorkoutStep.id`) for anything already logged stays
    /// valid.
    static func applyToSession(instruction: String, session: WorkoutSession) {
        let lower = instruction.lowercased()

        if let (from, to) = parseSwap(lower) {
            renameInSession(from: from, to: to, session: session)
            return
        }

        if lower.contains("drop set") {
            addDropSetInSession(lower, session: session)
            return
        }

        if let direction = volumeDirection(lower) {
            adjustVolumeInSession(lower, direction: direction, session: session)
        }
    }

    private static func renameInSession(from: String, to: String, session: WorkoutSession) {
        let newName = to.capitalizingFirstLetterOfEachWord()
        for idx in session.steps.indices {
            guard case .set(var info) = session.steps[idx].page,
                  info.exercise.name.range(of: from, options: .caseInsensitive) != nil else { continue }
            info.exercise = Exercise(name: newName, cue: info.exercise.cue, target: info.exercise.target, moodKey: info.exercise.moodKey)
            session.steps[idx].page = .set(info)
            session.steps[idx].exerciseName = newName
        }
    }

    private static func addDropSetInSession(_ lower: String, session: WorkoutSession) {
        guard let lastIndex = session.steps.lastIndex(where: { step in
            if case .set(let info) = step.page { return matches(lower, name: info.exercise.name) }
            return false
        }), case .set(let info) = session.steps[lastIndex].page else { return }

        let dropTarget: SetTarget
        switch info.exercise.target {
        case .reps(let count, let weight):
            dropTarget = .reps(count: count + 4, weight: weight.map { max($0 * 0.8, 5).rounded() })
        case .timed(let seconds):
            dropTarget = .timed(seconds: seconds)
        }
        let dropExercise = Exercise(name: info.exercise.name, cue: info.exercise.cue, target: dropTarget, moodKey: info.exercise.moodKey)
        let dropInfo = SetPageInfo(
            exercise: dropExercise,
            setNumber: info.setNumber + 1,
            totalSets: info.totalSets + 1,
            groupLabel: info.groupLabel,
            groupKind: info.groupKind,
            round: info.round,
            totalRounds: info.totalRounds,
            miniMap: info.miniMap
        )
        let step = WorkoutStep(
            blockIndex: session.steps[lastIndex].blockIndex,
            blockName: session.steps[lastIndex].blockName,
            moodKey: info.exercise.moodKey,
            page: .set(dropInfo),
            exerciseName: info.exercise.name
        )
        session.steps.insert(step, at: lastIndex + 1)
    }

    private static func adjustVolumeInSession(_ lower: String, direction: VolumeDirection, session: WorkoutSession) {
        guard let currentIndex = session.activeIndex else { return }
        // Only touch not-yet-reached sets, walking backwards so repeated removals/insertions don't
        // shift not-yet-visited indices out from under the loop.
        var i = session.steps.count - 1
        while i > currentIndex {
            guard case .set(let info) = session.steps[i].page, matches(lower, name: info.exercise.name) else {
                i -= 1
                continue
            }
            switch direction {
            case .reduce:
                session.steps.remove(at: i)
            case .increase:
                let duplicate = session.steps[i]
                let clone = WorkoutStep(blockIndex: duplicate.blockIndex, blockName: duplicate.blockName, moodKey: duplicate.moodKey, page: duplicate.page, exerciseName: duplicate.exerciseName)
                session.steps.insert(clone, at: i + 1)
            }
            i -= 1
        }
    }

    // MARK: - Shared parsing

    private static func volumeDirection(_ lower: String) -> VolumeDirection? {
        guard lower.contains("volume") else { return nil }
        if lower.contains("reduce") || lower.contains("cut") || lower.contains("less") { return .reduce }
        if lower.contains("increase") || lower.contains("add") || lower.contains("more") { return .increase }
        return nil
    }

    /// Matches "swap X for Y" / "swap X with Y" / "replace X with Y" / "replace X for Y".
    private static func parseSwap(_ lower: String) -> (from: String, to: String)? {
        for verb in ["swap ", "replace "] {
            guard let verbRange = lower.range(of: verb) else { continue }
            for separator in [" for ", " with "] {
                guard let sepRange = lower.range(of: separator, range: verbRange.upperBound..<lower.endIndex) else { continue }
                let from = String(lower[verbRange.upperBound..<sepRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                var to = String(lower[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                to = to.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !from.isEmpty, !to.isEmpty { return (from, to) }
            }
        }
        return nil
    }

    private static func matches(_ lower: String, name: String) -> Bool {
        lower.contains(name.lowercased())
    }

    private static func findExercise(named name: String, in exercises: [PlanExerciseRecord]) -> PlanExerciseRecord? {
        exercises.first { $0.name.lowercased().contains(name) || name.contains($0.name.lowercased()) }
    }

    /// "add a drop set [to X]" — uses the named exercise if the instruction mentions one, otherwise
    /// falls back to the plan's last exercise (the model typically means "the one just discussed").
    private static func matchSingleExercise(_ lower: String, in exercises: [PlanExerciseRecord]) -> PlanExerciseRecord? {
        for exercise in exercises where lower.contains(exercise.name.lowercased()) {
            return exercise
        }
        return exercises.last
    }

    private static func matchingExercises(_ lower: String, in exercises: [PlanExerciseRecord]) -> [PlanExerciseRecord] {
        for (keyword, terms) in bodyPartKeywords where lower.contains(keyword) {
            let matched = exercises.filter { exercise in terms.contains { exercise.name.lowercased().contains($0) } }
            if !matched.isEmpty { return matched }
        }
        // No recognized body-part keyword — if a specific exercise is named, target just that one.
        for exercise in exercises where lower.contains(exercise.name.lowercased()) {
            return [exercise]
        }
        return []
    }

    private static func addDropSet(to exercise: PlanExerciseRecord) {
        let sets = exercise.orderedSets
        guard let last = sets.last else { return }
        let isTimed = last.seconds != nil
        let dropReps = isTimed ? nil : (last.reps ?? 8) + 4
        let dropWeight = isTimed ? nil : last.weight.map { max($0 * 0.8, 5).rounded() }
        exercise.sets.append(PlanSetRecord(order: sets.count, reps: dropReps, weight: dropWeight, seconds: last.seconds))
    }

    private static func adjustVolume(_ exercise: PlanExerciseRecord, direction: VolumeDirection) {
        let sets = exercise.orderedSets
        switch direction {
        case .reduce:
            guard sets.count > 1, let removed = sets.last else { return }
            exercise.sets.removeAll { $0.id == removed.id }
        case .increase:
            guard let last = sets.last else { return }
            exercise.sets.append(PlanSetRecord(order: sets.count, reps: last.reps, weight: last.weight, seconds: last.seconds))
        }
    }
}

private extension String {
    /// Title-cases a free-text exercise name the model gave in lowercase prose (e.g. "machine row"
    /// → "Machine Row") for display/storage consistency with the rest of the plan.
    func capitalizingFirstLetterOfEachWord() -> String {
        split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
