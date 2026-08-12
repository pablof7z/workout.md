import SwiftUI
import SwiftData

/// "Coach-generated from a goal" plan creation (slice 8): a real coach conversation
/// (`CoachConversationView`, the same surface `OnboardingView` uses) where the athlete states a
/// goal in plain language and the coach calls `plan_apply` to create+activate (or edit, if one is
/// already active) the plan. Previously this drove a bespoke one-shot structured-JSON generation
/// turn (`CoachController.generatePlan`/`ProposedPlan`) — removed per domain-primitives.md
/// invariants 1/2: the coach creates plans through exactly one mechanism, `plan_apply`, never a
/// second parallel pipeline.
struct GeneratePlanSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BackgroundView(moodKey: .rest)
                .ignoresSafeArea()

            CoachConversationView(
                mode: .planning,
                headline: "Tell me your goal and I'll build a plan.",
                placeholder: "e.g. Upper body, 45 min, hypertrophy…",
                readyLabel: "Use This Plan",
                skipLabel: "Cancel",
                proposalOnly: true,
                onActivePlan: { dismiss() },
                onSkip: { dismiss() }
            )
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }
}
