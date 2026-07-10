import SwiftUI

/// The floating glass control cluster docked to the bottom safe area. After the interaction rework
/// this is intentionally minimal: a small icon-only effort button and a Skip — reps/weight are no
/// longer edited down here, they're the always-visible floating rows on the set page itself (see
/// `StepPageView.FloatingTargetRows`). There is NO Log & Next — advancing is a swipe down on the
/// vertical pager — and no Note button (notes live on the Coach screen). Besides the coach cue pill,
/// this is the only place in the runner that uses Liquid Glass — reserved for floating controls,
/// never content.
struct ControlsView: View {
    @Environment(WorkoutSession.self) private var session
    let step: WorkoutStep
    let isLast: Bool
    var onSkip: () -> Void
    var onFinish: () -> Void

    @State private var effortExpanded = false

    var body: some View {
        VStack(spacing: 12) {
            if case .set = step.page {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        EffortControl(committed: session.rpe[step.id], expanded: $effortExpanded) { value in
                            session.setEffort(value, for: step.id)
                        }

                        if !effortExpanded {
                            Spacer(minLength: 0)

                            if isLast {
                                Button {
                                    Haptics.impact(.medium)
                                    onFinish()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "flag.checkered")
                                        Text("Finish")
                                    }
                                    .font(.subheadline.weight(.bold))
                                    .frame(height: 44)
                                    .padding(.horizontal, 18)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(.green)
                                .accessibilityLabel("Finish workout")
                            } else {
                                Button(action: onSkip) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "forward.end")
                                        Text("Skip")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(height: 44)
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .accessibilityLabel("Skip this set")
                            }
                        }
                    }
                    .animation(.snappy(duration: 0.32), value: effortExpanded)
                }
            } else if isLast {
                // A rest page can't be the last step in this workout, but guard anyway.
                Button {
                    Haptics.impact(.medium)
                    onFinish()
                } label: {
                    Text("Finish")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
            }
        }
        .padding(.horizontal, 20)
    }
}
