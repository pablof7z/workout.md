import Foundation
import SwiftData

/// Assembles the bounded context blocks `CoachController.converse` folds in alongside the
/// athlete's own text — one call site so every `CoachMode` (onboarding/planning/today/
/// activeWorkout/exercise/historyReview) draws from the same primitives instead of each having its
/// own ad hoc grounding, per `docs/architecture/domain-primitives.md` §6. Every block is terse,
/// independently omittable, and read FRESH on every call — straight from SwiftData/the live
/// `WorkoutSession`, never cached — so the "whenever memories/plan/session change, the digest is
/// recomputed for the next call" invariant holds without a separate cache-invalidation step.
enum CoachContextAssembler {

    /// Builds the full context block for one turn, blank-line-separated, empty sub-blocks dropped.
    static func build(
        mode: CoachMode,
        session: WorkoutSession?,
        focusExercise: String?,
        modelContext: ModelContext,
        settings: AppSettings,
        fabric: FabricController
    ) -> String {
        var blocks: [String] = []

        // Durable memory — always folded in, the ONE source of truth for grounding
        // (domain-primitives.md §5/§6, invariant 4). Athlete facts (goals, schedule, equipment,
        // constraints, preferences) are never settings the user fills in — they're things the coach
        // learns via `memory_add` during onboarding and ongoing chat. An empty digest (fresh install,
        // before onboarding has captured anything) is fine and simply omitted.
        let memoryDigest = MemoryStore(context: modelContext).digest()
        if !memoryDigest.isEmpty { blocks.append(memoryDigest) }

        // The dedicated "new plan" conversation is intentionally clean-room: its draft starts
        // empty, so including the currently active plan here would encourage the model to edit/copy
        // it even though the proposal host cannot address those persisted IDs.
        if mode != .planning, let planBlock = planSummary(modelContext: modelContext) {
            blocks.append(planBlock)
        }

        // Recent completed history matters for planning/repair/review turns; a live in-set turn
        // doesn't need it (the live session grounding below already covers "what's happening now").
        switch mode {
        case .planning, .today, .historyReview:
            let history = recentHistorySummary(modelContext: modelContext)
            if !history.isEmpty { blocks.append(history) }
        case .onboarding, .activeWorkout, .exercise:
            break
        }

        if settings.doctrineEnabled {
            let doctrine = DoctrineStore.shared.digest()
            if !doctrine.isEmpty { blocks.append(doctrine) }
        }

        let review = CoachReviewStore.shared.contextSnippet()
        if !review.isEmpty { blocks.append(review) }

        let fabricContext = fabric.contextSnippet()
        if !fabricContext.isEmpty { blocks.append(fabricContext) }

        // Live session grounding — only when a workout is actually running; this is what lets
        // `session_apply` (`AppCoachHost`) address sets by stable id.
        if let session {
            blocks.append(session.sessionGrounding())
            if let focusExercise {
                blocks.append("Currently focused on: \(focusExercise)")
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    // MARK: - Active plan summary

    /// A terse name/goal/next-session/blocks summary — enough for the coach to reference the plan
    /// in conversation without a wasted `plan_get` round-trip; the model still calls `plan_get` for
    /// full detail (stable ids) before editing.
    private static func planSummary(modelContext: ModelContext) -> String? {
        guard let snapshot = PlanRepository(context: modelContext).activeSnapshot() else { return nil }

        var lines = ["Active plan: \(snapshot.name)"]
        if let goal = snapshot.goal, !goal.isEmpty {
            lines.append("Goal: \(goal)")
        }
        if let next = snapshot.nextSession {
            let blockLabels = next.blocks.map(\.label).joined(separator: ", ")
            lines.append("Next session: \(next.name)" + (blockLabels.isEmpty ? "" : " — \(blockLabels)"))
        }
        let sessionWord = snapshot.sessions.count == 1 ? "session" : "sessions"
        lines.append("\(snapshot.sessions.count) \(sessionWord) total. Call plan_get for full detail with ids.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Recent history

    private static func recentHistorySummary(modelContext: ModelContext, limit: Int = 3) -> String {
        var descriptor = FetchDescriptor<WorkoutRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        guard let records = try? modelContext.fetch(descriptor), !records.isEmpty else { return "" }

        let lines = records.map { record in "- \(record.name) on \(dateFormatter.string(from: record.date))" }
        return (["Recent completed sessions:"] + lines).joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
