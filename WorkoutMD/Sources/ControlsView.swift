import SwiftUI

/// The floating glass control cluster docked to the bottom safe area. After the interaction rework
/// this is intentionally light: an expressive effort rating, the reps stepper (rep sets only), and
/// a small Skip. There is NO Log & Next — advancing is a swipe down on the vertical pager — and no
/// Note button (notes live on the Coach screen). Besides the coach cue pill, this is the only place
/// in the runner that uses Liquid Glass — reserved for floating controls, never content.
struct ControlsView: View {
    @Environment(WorkoutSession.self) private var session
    let step: WorkoutStep
    let isLast: Bool
    var onSkip: () -> Void
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if case .set(let info) = step.page {
                EffortControl(committed: session.rpe[step.id]) { value in
                    session.setEffort(value, for: step.id)
                }

                HStack(spacing: 12) {
                    if case .reps = info.exercise.target {
                        RepsNudgeRow(stepID: step.id)
                    }

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

/// Inline reps nudge for rep-based sets only (hidden on timed sets, which use the countdown
/// timer instead). Big, bold reps value flanked by two 52pt glass circle steppers. Edits the
/// shared session's step target directly, so the runner's hero updates live.
private struct RepsNudgeRow: View {
    @Environment(WorkoutSession.self) private var session
    let stepID: WorkoutStep.ID

    private var displayedReps: Int {
        guard let idx = session.steps.firstIndex(where: { $0.id == stepID }),
              case .set(let info) = session.steps[idx].page,
              case .reps(let count, _) = info.exercise.target else { return 0 }
        return count
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("Reps")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    StepperCircle(symbol: "minus", label: "Decrease reps") {
                        Haptics.selection()
                        session.adjustReps(forStepID: stepID, delta: -1)
                    }

                    Text("\(displayedReps)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 46)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: displayedReps)

                    StepperCircle(symbol: "plus", label: "Increase reps") {
                        Haptics.selection()
                        session.adjustReps(forStepID: stepID, delta: 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(displayedReps) reps")
    }
}

/// A 52pt circular glass stepper button with a bold glyph.
private struct StepperCircle: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}
