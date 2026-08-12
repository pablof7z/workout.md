import Foundation
import SwiftData

/// Executes every coach tool call for an app-level `CoachController.converse` turn — see
/// `docs/architecture/domain-primitives.md` §6/§7. Replaces `WorkoutSessionCoachHost`'s five
/// narrow tools with the ten general primitives Rust `tools.rs` now registers:
/// `plan_get`/`plan_apply`/`plan_revisions`/`plan_restore` (always available — route to
/// `PlanRepository`), `memory_add`/`memory_update`/`memory_query`/`memory_remove` (always
/// available — route to `MemoryStore`), `session_apply` (only meaningful when a workout is
/// live — routes to `WorkoutSession`'s by-stable-id mutation methods), and `escalate_to_reasoning`
/// (routes to `onEscalate`, which `CoachController.converse` uses to re-run this turn on the
/// reasoning tier — see its "Escalation" doc section). Unlike `WorkoutSessionCoachHost`, this host
/// works with or without a live `session` — the coach is an app-level service now, not something
/// `WorkoutSession` owns.
///
/// Called from the coach engine's background tokio thread — every mutation is marshaled onto the
/// main thread via `DispatchQueue.main.sync`, which blocks only that background thread (never the
/// UI) until the main-thread work — and the confirmation string it produces — is ready, satisfying
/// `CoachHost.applyTool`'s synchronous, value-returning contract.
final class AppCoachHost: CoachHost, @unchecked Sendable {
    enum PlanToolBehavior: Sendable {
        case applyImmediately
        case buildProposal(PlanSnapshot?)
    }

    let modelContext: ModelContext
    /// `nil` when this turn has no live workout attached (onboarding, planning, Today's "what's
    /// next" repair, a finished-history review, ...) — `session_apply` reports a clear "no live
    /// workout" error in that case rather than crashing or silently no-op'ing.
    weak var session: WorkoutSession?
    /// The exercise this turn is scoped to, if any — folded into a notable fabric post so the
    /// summary reads the same way `WorkoutSessionCoachHost`'s did (`"Bench Press: ..."`).
    let focusExercise: String?
    let fabric: FabricController?
    private let onDiff: (String) -> Void
    /// Invoked when the model calls `escalate_to_reasoning` — signals `CoachController.converse` to
    /// re-run this turn on the reasoning tier once the fast turn's own sink completes. Defaults to a
    /// no-op so existing call sites/tests that don't care about escalation keep compiling;
    /// `CoachController` passes the real one.
    private let onEscalate: () -> Void
    private let planToolBehavior: PlanToolBehavior
    private let onPlanProposal: (PlanSnapshot) -> Void

    /// Tool names whose confirmation is a genuine, concrete change to the plan or the live workout
    /// — worth a terse fabric post so the user's other agents see it land — mirroring
    /// `WorkoutSessionCoachHost.notableTools`. `memory_*`/`plan_get`/`plan_revisions` are reads or
    /// freestanding notes, not numeric changes the fabric needs to know about turn by turn.
    private static let notableTools: Set<String> = ["plan_apply", "plan_restore", "session_apply"]
    private static let userVisibleTools: Set<String> = [
        "plan_apply", "plan_restore", "session_apply", "memory_add", "memory_update", "memory_remove"
    ]

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    init(
        modelContext: ModelContext,
        session: WorkoutSession? = nil,
        focusExercise: String? = nil,
        fabric: FabricController? = nil,
        planToolBehavior: PlanToolBehavior = .applyImmediately,
        onPlanProposal: @escaping (PlanSnapshot) -> Void = { _ in },
        onDiff: @escaping (String) -> Void = { _ in },
        onEscalate: @escaping () -> Void = {}
    ) {
        self.modelContext = modelContext
        self.session = session
        self.focusExercise = focusExercise
        self.fabric = fabric
        self.planToolBehavior = planToolBehavior
        self.onPlanProposal = onPlanProposal
        self.onDiff = onDiff
        self.onEscalate = onEscalate
    }

    func applyTool(name: String, argsJson: String) -> String {
        let work = { [self] in
            let confirmation = dispatch(name: name, argsJson: argsJson)
            // Read tools return machine context to the model. They must never become transcript
            // lines; doing so leaked complete plan JSON into the customer-facing conversation.
            if Self.userVisibleTools.contains(name), shouldShowToolResult(name) {
                onDiff(confirmation)
            }
            if Self.notableTools.contains(name), shouldPublishToolResult(name) {
                let body = focusExercise.map { "\($0): \(confirmation)" } ?? confirmation
                fabric?.postSummary(body)
            }
            return confirmation
        }
        // Rust invokes tools from its tokio thread; Foundation Models currently invokes Tool.call
        // concurrently as well. Keep the boundary safe if a future framework version calls a tool
        // on the main thread instead of synchronously dispatching back onto that same thread.
        return Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    private func shouldShowToolResult(_ name: String) -> Bool {
        if name == "plan_apply", case .buildProposal = planToolBehavior { return false }
        return true
    }

    private func shouldPublishToolResult(_ name: String) -> Bool {
        // A proposal is not a plan change until the athlete accepts it. Do not announce drafts to
        // the fabric as if they had landed.
        if name == "plan_apply", case .buildProposal = planToolBehavior { return false }
        return true
    }

    // MARK: - Dispatch

    private func dispatch(name: String, argsJson: String) -> String {
        switch name {
        case "plan_get": return planGet()
        case "plan_apply": return planApply(argsJson)
        case "plan_revisions": return planRevisions()
        case "plan_restore": return planRestore(argsJson)
        case "memory_add": return memoryAdd(argsJson)
        case "memory_update": return memoryUpdate(argsJson)
        case "memory_query": return memoryQuery(argsJson)
        case "memory_remove": return memoryRemove(argsJson)
        case "session_apply": return sessionApply(argsJson)
        case "escalate_to_reasoning": return escalateToReasoning()
        default: return "Unknown tool \(name)."
        }
    }

    // MARK: - plan_get

    private func planGet() -> String {
        let snapshot: PlanSnapshot?
        switch planToolBehavior {
        case .applyImmediately:
            snapshot = PlanRepository(context: modelContext).activeSnapshot()
        case .buildProposal(let draft):
            snapshot = draft
        }
        guard let snapshot,
              let data = try? Self.encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8)
        else {
            return #"{"message":"No active plan yet."}"#
        }
        return json
    }

    // MARK: - plan_apply

    private struct PlanApplyArgs: Decodable {
        let operations: [PlanOp]
        let propose: Bool?
        let summary: String?
    }

    /// If there's already an active plan, `operations` is applied (or proposed) against it. If
    /// there is NO active plan yet, `plan_apply` is also how onboarding/first-run creates one —
    /// `propose` is ignored in that branch (there's nothing stored yet to preview against; the new
    /// plan is created and activated directly, same as `PlanRepository.createPlan`'s contract).
    private func planApply(_ argsJson: String) -> String {
        guard let args = decode(PlanApplyArgs.self, from: argsJson) else {
            return "Could not parse plan_apply arguments."
        }
        let mutation = PlanMutation(operations: args.operations, summary: args.summary)
        let repository = PlanRepository(context: modelContext)

        do {
            if case .buildProposal(let currentDraft) = planToolBehavior {
                let base = currentDraft ?? PlanEngine.empty(
                    name: Self.derivePlanName(from: mutation) ?? "My Plan")
                let proposal = try PlanEngine.apply(mutation, to: base)
                onPlanProposal(proposal)
                let summary = mutation.summary ?? PlanEngine.summarize(mutation)
                return "Prepared a plan proposal: \(summary). The athlete can review it on screen."
            }

            if let activePlanID = repository.activeSnapshot()?.id {
                let mode: PlanRepository.PlanApplyMode = (args.propose ?? false) ? .propose : .apply
                let result = try repository.apply(mutation, to: activePlanID, mode: mode)
                if !result.proposed {
                    // domain-primitives.md §11: keep `plan.md` no more than one applied coach turn
                    // stale. `.propose` mode persists nothing, so there's deliberately nothing to
                    // sync yet for that branch.
                    let snapshot = result.snapshot
                    Task { await SyncManager.shared.commitPlan(snapshot) }
                }
                return planApplyConfirmation(result, mutation: mutation)
            } else {
                let name = Self.derivePlanName(from: mutation) ?? "My Plan"
                let plan = try repository.createPlan(mutation, name: name, activate: true)
                if let snapshot = repository.snapshot(of: plan.id) {
                    Task { await SyncManager.shared.commitPlan(snapshot) }
                }
                return "Created and activated plan \"\(plan.name)\" (\(PlanEngine.summarize(mutation)))."
            }
        } catch {
            return "Could not apply plan change: \(Self.describe(error))"
        }
    }

    private func planApplyConfirmation(_ result: PlanRepository.PlanApplyResult, mutation: PlanMutation) -> String {
        let summary = mutation.summary ?? PlanEngine.summarize(mutation)
        guard result.proposed else { return "Applied: \(summary)" }
        return "Proposed (not applied): \(summary)"
    }

    /// Looks for a `setPlanMeta` op that sets a non-blank `name`, for naming a brand-new plan when
    /// the coach's batch didn't already imply one via `createPlan`'s own `name:` argument path.
    private static func derivePlanName(from mutation: PlanMutation) -> String? {
        for op in mutation.operations {
            guard case let .setPlanMeta(name, _, _) = op, case let .set(value) = name else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    // MARK: - plan_revisions

    private func planRevisions() -> String {
        guard let activePlanID = PlanRepository(context: modelContext).activeSnapshot()?.id else { return "[]" }
        let revisions = PlanRepository(context: modelContext).revisions(of: activePlanID)
        let payload = revisions.map { revision -> [String: String] in
            ["id": revision.id.uuidString, "summary": revision.summary, "createdAt": ISO8601DateFormatter().string(from: revision.createdAt)]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - plan_restore

    private struct PlanRestoreArgs: Decodable { let revision_id: String }

    private func planRestore(_ argsJson: String) -> String {
        guard let args = decode(PlanRestoreArgs.self, from: argsJson),
              let revisionID = UUID(uuidString: args.revision_id)
        else {
            return "Could not parse plan_restore arguments."
        }
        do {
            let result = try PlanRepository(context: modelContext).restore(revisionID: revisionID)
            return "Restored plan \"\(result.snapshot.name)\" to a previous revision."
        } catch {
            return "Could not restore revision: \(Self.describe(error))"
        }
    }

    // MARK: - memory_add / memory_update / memory_query / memory_remove

    private struct MemoryAddArgs: Decodable { let text: String; let tags: [String]? }

    private func memoryAdd(_ argsJson: String) -> String {
        guard let args = decode(MemoryAddArgs.self, from: argsJson) else {
            return "Could not parse memory_add arguments."
        }
        MemoryStore(context: modelContext).add(text: args.text, tags: args.tags ?? [], source: "coach")
        return "Remembered: \(args.text)"
    }

    private struct MemoryUpdateArgs: Decodable { let id: String; let text: String?; let tags: [String]? }

    private func memoryUpdate(_ argsJson: String) -> String {
        guard let args = decode(MemoryUpdateArgs.self, from: argsJson), let id = UUID(uuidString: args.id) else {
            return "Could not parse memory_update arguments."
        }
        MemoryStore(context: modelContext).update(id: id, text: args.text, tags: args.tags)
        return "Updated memory."
    }

    private struct MemoryQueryArgs: Decodable { let query: String?; let tags: [String]?; let limit: Int? }

    private func memoryQuery(_ argsJson: String) -> String {
        // All fields are optional — `{}` is a valid "list everything" call, so an empty/`nil`
        // decode (rather than the malformed-JSON fallback the other tools use) falls back to the
        // all-optional default instead of surfacing a spurious parse error.
        let args = decode(MemoryQueryArgs.self, from: argsJson) ?? MemoryQueryArgs(query: nil, tags: nil, limit: nil)
        let results = MemoryStore(context: modelContext).query(text: args.query, tags: args.tags ?? [], limit: args.limit)
        let payload = results.map { memory -> [String: Any] in
            ["id": memory.id.uuidString, "text": memory.text, "tags": memory.tags]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private struct MemoryRemoveArgs: Decodable { let id: String }

    private func memoryRemove(_ argsJson: String) -> String {
        guard let args = decode(MemoryRemoveArgs.self, from: argsJson), let id = UUID(uuidString: args.id) else {
            return "Could not parse memory_remove arguments."
        }
        MemoryStore(context: modelContext).remove(id: id)
        return "Removed memory."
    }

    // MARK: - session_apply

    private struct SessionApplyArgs: Decodable { let operations: [SessionOp] }

    /// Applies every `SessionOp` in order against the live `session`, addressing sets by their
    /// stable `WorkoutStep.id` (surfaced to the model via `WorkoutSession.sessionGrounding()` —
    /// see `CoachContextAssembler`). No live session ⇒ a plain, honest error string rather than a
    /// crash or a silent no-op, since the model may call this speculatively.
    private func sessionApply(_ argsJson: String) -> String {
        guard let session else { return "No live workout to modify." }
        guard let args = decode(SessionApplyArgs.self, from: argsJson) else {
            return "Could not parse session_apply arguments."
        }
        let confirmations = args.operations.map { op -> String in
            switch op {
            case let .adjustSet(setID, reps, weight):
                return session.setTarget(reps: reps, weight: weight, forStepID: setID)
            case let .skipSet(setID):
                return session.skip(forStepID: setID)
            case let .substituteExercise(exerciseName, newName):
                return session.substitute(exerciseName: exerciseName, newName: newName)
            case let .addSet(afterSetID, reps, weight):
                return session.addSet(afterStepID: afterSetID, reps: reps, weight: weight)
            }
        }
        return confirmations.joined(separator: "; ")
    }

    // MARK: - escalate_to_reasoning

    /// `reason` (if the model sent one) is accepted by the Rust tool schema but not surfaced
    /// anywhere here — the tool exists purely to flip `onEscalate`, which is what actually re-runs
    /// this turn on the reasoning tier (`CoachController.converse`'s "Escalation" doc section).
    private func escalateToReasoning() -> String {
        onEscalate()
        return "Switching to the reasoning model to work through this."
    }

    // MARK: - Shared helpers

    private func decode<T: Decodable>(_ type: T.Type, from argsJson: String) -> T? {
        try? Self.decoder.decode(T.self, from: Data(argsJson.utf8))
    }

    private static func describe(_ error: Error) -> String {
        if let engineError = error as? PlanEngineError {
            switch engineError {
            case .unknownID(let id): return "unknown id \(id.uuidString)."
            case .indexOutOfRange: return "index out of range."
            case .invalidMove: return "invalid move."
            case .emptyPlanName: return "plan name cannot be empty."
            }
        }
        if let repositoryError = error as? PlanRepository.PlanRepositoryError {
            switch repositoryError {
            case .planNotFound(let id): return "plan \(id.uuidString) not found."
            case .revisionNotFound(let id): return "revision \(id.uuidString) not found."
            }
        }
        return String(describing: error)
    }
}

// MARK: - SessionOp
//
// The `session_apply` operation vocabulary (domain-primitives.md §7, `core/workout-core/src/
// coach/tools.rs`'s `SessionApplyTool` description): a flat `{"op":...}` object per element,
// mirroring `PlanOp`'s wire-shape convention but decode-only — these are never re-encoded, so
// there's no `Codable` symmetry to maintain the way `PlanOp` has.
private enum SessionOp: Decodable {
    /// `{"op":"adjustSet","setID":"<uuid>","reps":8,"weight":225}` — omit a field to leave it
    /// unchanged.
    case adjustSet(setID: UUID, reps: Int?, weight: Double?)
    /// `{"op":"skipSet","setID":"<uuid>"}`
    case skipSet(setID: UUID)
    /// `{"op":"substituteExercise","exerciseName":"...","newName":"..."}` — addresses by exercise
    /// name (there may be several sets sharing it), not by a single set id.
    case substituteExercise(exerciseName: String, newName: String)
    /// `{"op":"addSet","afterSetID":"<uuid>","reps":10,"weight":null}`
    case addSet(afterSetID: UUID, reps: Int?, weight: Double?)

    private enum Op: String, Decodable { case adjustSet, skipSet, substituteExercise, addSet }

    private enum CodingKeys: String, CodingKey {
        case op, setID, reps, weight, exerciseName, newName, afterSetID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Op.self, forKey: .op) {
        case .adjustSet:
            self = .adjustSet(
                setID: try Self.decodeUUID(forKey: .setID, from: container),
                reps: try container.decodeIfPresent(Int.self, forKey: .reps),
                weight: try container.decodeIfPresent(Double.self, forKey: .weight)
            )
        case .skipSet:
            self = .skipSet(setID: try Self.decodeUUID(forKey: .setID, from: container))
        case .substituteExercise:
            self = .substituteExercise(
                exerciseName: try container.decode(String.self, forKey: .exerciseName),
                newName: try container.decode(String.self, forKey: .newName)
            )
        case .addSet:
            self = .addSet(
                afterSetID: try Self.decodeUUID(forKey: .afterSetID, from: container),
                reps: try container.decodeIfPresent(Int.self, forKey: .reps),
                weight: try container.decodeIfPresent(Double.self, forKey: .weight)
            )
        }
    }

    private static func decodeUUID(
        forKey key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> UUID {
        let raw = try container.decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid UUID string: \(raw)")
        }
        return uuid
    }
}
