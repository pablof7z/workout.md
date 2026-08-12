import SwiftUI
import SwiftData

/// Onboarding is complete when the user has a usable active plan, or explicitly opts out of having
/// one — never merely because a slide deck was dismissed. See `docs/architecture/domain-primitives.md`
/// §9. Extracted as a pure function (rather than inlined in the view) so the condition the "You're
/// set" button keys on is unit-testable without driving SwiftUI.
enum OnboardingCompletion {
    static func isComplete(activePlans: [PlanRecord]) -> Bool {
        activePlans.first != nil
    }
}

/// Replaces the old 3-slide gate with a real coach conversation (`CoachMode.onboarding`,
/// domain-primitives.md §9). A new user dictates or types a long unstructured account, a routine, or
/// builds a plan collaboratively; the coach records memories via `memory_add` and normally creates
/// and activates a plan via `plan_apply`. Just a thin wrapper around `CoachConversationView` (slice
/// 8: extracted so this exact conversation surface is shared with `GeneratePlanSheet` rather than
/// onboarding driving a real coach turn while plan-from-goal drove a separate structured-JSON
/// pipeline) — full-bleed dark background is applied here since `CoachConversationView` itself is
/// background-agnostic (the sheet contexts it's also used from want their own presentation chrome).
struct OnboardingView: View {
    var onFinished: () -> Void

    var body: some View {
        ZStack {
            BackgroundView(moodKey: .rest)
                .ignoresSafeArea()

            CoachConversationView(
                mode: .onboarding,
                headline: "Tell me about your training and I'll build your plan.",
                onActivePlan: onFinished,
                onSkip: onFinished
            )
        }
        .preferredColorScheme(.dark)
    }
}
