import Foundation

/// The coach-generated-plan flow (product spec item: "coach-generated from a goal") is implemented
/// as a dedicated coach turn that asks for a structured JSON reply and parses it here on the Swift
/// side — the simpler, robust path the spec explicitly allows instead of a new Rust-core tool +
/// bindings regen. `CoachController.generatePlan` (in `CoachController.swift`) drives the turn;
/// everything below is the request/response shape and its parsing.

/// Decodes the coach's JSON plan proposal. Every field is deliberately permissive (optionals with
/// sane fallbacks in `makePlanRecord`) because the model's JSON, while asked to conform exactly,
/// is never fully trustworthy.
struct ProposedPlan: Decodable {
    struct Set: Decodable {
        let reps: Int?
        let weight: Double?
        let seconds: Int?
    }

    struct Exercise: Decodable {
        let name: String
        let cue: String?
        let sets: [Set]?
    }

    struct Block: Decodable {
        let kind: String
        let label: String?
        let rounds: Int?
        let restSeconds: Int?
        let exercises: [Exercise]?
    }

    let name: String?
    let goal: String?
    let blocks: [Block]?

    /// Extracts the first `{...}` JSON object from `text` (tolerating a model that wraps its reply
    /// in a ```json code fence or a stray sentence despite being told not to) and decodes it.
    static func parse(_ text: String) -> ProposedPlan? {
        guard let jsonString = extractJSONObject(from: text) else { return nil }
        return try? JSONDecoder().decode(ProposedPlan.self, from: Data(jsonString.utf8))
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }

    /// Builds a fresh, not-yet-inserted `PlanRecord` graph from the parsed proposal. Never returns
    /// an unusable plan: a missing/empty `blocks` array (or a block with no exercises) still yields
    /// at least one straight-sets placeholder block, so the caller always gets something startable.
    func makePlanRecord() -> PlanRecord {
        let plan = PlanRecord(name: (name?.isEmpty == false ? name! : "Coach Plan"), goal: goal)

        for (blockIndex, block) in (blocks ?? []).enumerated() {
            let kind = PlanBlockKind(rawValue: block.kind.lowercased()) ?? .straight
            let exercisesInput = block.exercises ?? []
            guard !exercisesInput.isEmpty else { continue }

            let rounds = block.rounds ?? 3
            let blockRecord = PlanBlockRecord(
                order: blockIndex,
                kind: kind,
                label: block.label?.isEmpty == false ? block.label! : kind.label,
                rounds: max(rounds, 1),
                restSeconds: block.restSeconds
            )

            for (exerciseIndex, exercise) in exercisesInput.enumerated() {
                let exerciseRecord = PlanExerciseRecord(order: exerciseIndex, name: exercise.name, cue: exercise.cue ?? "")
                let setsInput = exercise.sets ?? []
                if setsInput.isEmpty {
                    let count = kind == .straight ? 3 : max(rounds, 1)
                    exerciseRecord.sets = (0..<count).map { PlanSetRecord(order: $0, reps: 10, weight: nil) }
                } else {
                    exerciseRecord.sets = setsInput.enumerated().map { index, set in
                        PlanSetRecord(order: index, reps: set.reps, weight: set.weight, seconds: set.seconds)
                    }
                }
                blockRecord.exercises.append(exerciseRecord)
            }

            guard !blockRecord.exercises.isEmpty else { continue }
            plan.blocks.append(blockRecord)
        }

        if plan.blocks.isEmpty {
            let block = PlanBlockRecord(order: 0, kind: .straight, label: "Full Body")
            let exercise = PlanExerciseRecord(order: 0, name: "Goblet Squat", cue: "Chest up, sit between the heels.")
            exercise.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 12, weight: nil) }
            block.exercises = [exercise]
            plan.blocks = [block]
        }

        return plan
    }
}

enum PlanGenerationError: Error {
    case malformedResponse(String)
    case engineError(String)

    var userMessage: String {
        switch self {
        case .malformedResponse:
            return "The coach's reply couldn't be parsed into a plan. Try rephrasing the goal, or use the deterministic option below."
        case .engineError(let message):
            return message
        }
    }
}

/// A minimal `CoachSink` that just accumulates text and reports completion/error — no transcript,
/// no tool-call UI, since plan generation is a one-shot structured-JSON request rather than a
/// conversational turn. Mirrors `CoachStreamSink` in `CoachController.swift`'s threading contract:
/// every callback hops onto the main thread before touching its captured state.
final class PlanGenerationSink: CoachSink, @unchecked Sendable {
    private var accumulated = ""
    private let onCompleted: (String) -> Void
    private let onError: (String) -> Void

    init(onCompleted: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onCompleted = onCompleted
        self.onError = onError
    }

    func onTextDelta(delta: String) {
        DispatchQueue.main.async { [weak self] in
            self?.accumulated += delta
        }
    }

    func onToolCall(name: String, argsJson: String) {}

    func onCompleted(fullText: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onCompleted(fullText.isEmpty ? self.accumulated : fullText)
        }
    }

    func onError(message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onError(message)
        }
    }
}

/// Plan generation never expects a tool call (the system prompt asks for a bare JSON reply, no
/// tools are relevant), but `CoachEngine.sendMessage` requires a `CoachHost` regardless — this one
/// simply declines rather than crashing if the model calls one anyway.
final class NoopCoachHost: CoachHost, @unchecked Sendable {
    func applyTool(name: String, argsJson: String) -> String {
        "Not applicable while generating a plan proposal."
    }
}
