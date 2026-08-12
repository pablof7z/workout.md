import SwiftUI
import SwiftData

/// M5 — the "what should I do next?" surface: a prominent Today entry (outside a running session)
/// that asks the coach to propose or REPAIR the next session from recent history/goals. Per the
/// product spec's plan-repair principle, this is forward-only — no guilt, no catch-up, no streaks —
/// so a gap in training is surfaced as "here's the next useful session," never as a red missed-days
/// count. Falls back to a deterministic (coach-independent) repair — repeating the active plan under
/// a new name — when no coach provider is reachable, so the affordance always produces a startable
/// plan.
struct WhatsNextView: View {
    var onPlanReady: (PlanRecord) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(CoachController.self) private var coachController
    @Environment(AppSettings.self) private var appSettings

    @Query(sort: \WorkoutRecord.date, order: .reverse) private var sessions: [WorkoutRecord]
    @Query(filter: #Predicate<PlanRecord> { $0.isActive == true }) private var activePlans: [PlanRecord]
    @Query(sort: \PlanRecord.createdAt, order: .reverse) private var allPlans: [PlanRecord]

    @State private var isGenerating = false
    @State private var errorMessage: String?
    /// The coach's final reply text once `converse(mode: .today, ...)` completes — `plan_apply`
    /// (if the model called it) has already applied to the active plan by the time `onComplete`
    /// fires (`AppCoachHost.applyTool` runs synchronously before the turn's text finishes
    /// streaming), so this is shown as confirmation alongside a "Start This Session" button rather
    /// than a separate proposal object the way the deleted `generatePlan`/`ProposedPlan` pipeline
    /// used to hand back.
    @State private var coachReply: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let coachReply {
                    replyPreview(coachReply)
                } else if isGenerating {
                    Spacer()
                    ProgressView("Repairing your plan…")
                    Spacer()
                } else {
                    idleContent
                }
            }
            .padding()
            .navigationTitle("What's Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var idleContent: some View {
        Image(systemName: "sparkles")
            .font(.largeTitle)
            .foregroundStyle(.indigo)
            .padding(.top, 12)

        Text(contextSummary)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }

        Spacer()

        Button {
            generate()
        } label: {
            Text("Ask the Coach")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)

        Button {
            fallbackRepeat()
        } label: {
            Text("Repeat Active Plan Instead")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func replyPreview(_ reply: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let plan = activePlans.first {
                    Text(plan.name).font(.title2.weight(.bold))
                    Text(plan.summary).font(.subheadline).foregroundStyle(.secondary)

                    ForEach(plan.orderedBlocks) { block in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(block.label).font(.headline)
                            ForEach(block.orderedExercises) { exercise in
                                Text("• \(exercise.name) — \(exercise.orderedSets.count) set\(exercise.orderedSets.count == 1 ? "" : "s")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Text(reply)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Button {
            guard let plan = activePlans.first else { return }
            onPlanReady(plan)
        } label: {
            Text("Start This Session")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(activePlans.first == nil)

        Button(role: .destructive) {
            coachReply = nil
        } label: {
            Text("Discard")
                .frame(maxWidth: .infinity)
        }
    }

    private var contextSummary: String {
        guard let last = sessions.first else {
            return "No sessions logged yet. The coach will propose a starting plan for your goal."
        }
        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
        if days <= 1 {
            return "Last session: \(last.name), \(last.oneLineSummary). The coach will propose the next one."
        }
        return "Last session: \(last.name), \(days) days ago. No guilt, no catch-up — let's repair forward with the next useful session."
    }

    /// Routes the repair-forward request through the general conversation path (domain-primitives.md
    /// invariants 1/2: `plan_apply`, never a bespoke generation pipeline) instead of the deleted
    /// `CoachController.generatePlan`/`ProposedPlan`. `mode: .today` gets `CoachContextAssembler` to
    /// fold in recent history/goals the same way `.planning` does for a fresh plan.
    private func generate() {
        isGenerating = true
        errorMessage = nil
        coachReply = nil
        let prompt = Self.repairPrompt(sessions: sessions, activePlan: activePlans.first, settings: appSettings)
        coachController.converse(
            mode: .today,
            userText: prompt,
            modelContext: modelContext,
            onDelta: { _ in },
            onComplete: { text in
                isGenerating = false
                coachReply = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Plan updated." : text
            },
            onError: { message in
                isGenerating = false
                errorMessage = message
            }
        )
    }

    /// Coach-independent fallback: duplicates the active (or most recent) plan under a "repeat"
    /// name and activates it directly — still real plan CRUD, just without an LLM round-trip.
    private func fallbackRepeat() {
        guard let base = activePlans.first ?? allPlans.first else {
            errorMessage = "No plan exists yet to repeat — create one from the Plans screen first."
            return
        }
        let repaired = PlanStore.duplicate(base, newName: "\(base.name) (repeat)", context: modelContext)
        PlanStore.setActive(repaired, context: modelContext)
        onPlanReady(repaired)
    }

    /// Builds the repair-forward prompt: current plan, and — when there's a gap — an explicit
    /// instruction to repair forward without guilt/streak language. The athlete's stated goal is
    /// never passed in here — it already rides in via the coach memory digest that `converse`
    /// assembles on every turn (`CoachContextAssembler`).
    static func repairPrompt(sessions: [WorkoutRecord], activePlan: PlanRecord?, settings: AppSettings) -> String {
        var lines: [String] = []
        if let activePlan {
            lines.append("Current plan: \(activePlan.name) — \(activePlan.summary).")
        }
        if let last = sessions.first {
            let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
            lines.append("Last completed session: \(last.name), \(days) day(s) ago, \(last.oneLineSummary).")
            if days >= 4 {
                lines.append(
                    "There has been a \(days)-day gap. Repair forward: propose the single most useful " +
                    "next session given this reality. Do not add guilt, do not try to make up for missed " +
                    "volume, do not mention streaks or catching up."
                )
            } else {
                lines.append("Propose a sensible next session continuing this plan's progression.")
            }
        } else {
            lines.append("No completed sessions yet — propose a solid starting session for this goal.")
        }
        return lines.joined(separator: "\n")
    }
}
