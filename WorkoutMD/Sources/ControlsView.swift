import SwiftUI

/// The floating Finish button, docked to the bottom safe area, shown only once the pager has been
/// paged to the last page. Reps/weight are no longer edited down here (see
/// `StepPageView.FloatingTargetRows`), and neither is effort — effort is now reached by TAPPING
/// `StepPageView`'s round done/skip thumb, which opens `EffortPromptSheet` as a transient sheet
/// rather than living in a persistent overlay, so it can never collide with anything in this row.
/// There is NO Log & Next (that's the thumb) and no Skip button anymore either — skip is now the
/// thumb's left slide, which always acts on the ACTIVE set. Besides the coach cue pill, this is the
/// only other place in the runner that uses Liquid Glass.
struct ControlsView: View {
    let isLast: Bool
    var onFinish: () -> Void

    var body: some View {
        Group {
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
            }
        }
        .padding(.horizontal, 20)
    }
}
