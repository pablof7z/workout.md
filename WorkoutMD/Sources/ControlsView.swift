import SwiftUI

/// The floating Finish button, docked to the bottom safe area, shown only once the pager has been
/// paged to the last page. Reps/weight are no longer edited down here (see
/// `StepPageView.FloatingTargetRows`), and neither is effort — `EffortControl` moved to its own
/// top-trailing overlay in `RunnerView` specifically so it can never collide with `StepPageView`'s
/// round thumb, which owns bottom-CENTER and slides horizontally either side of it (a collapsed
/// effort button anywhere in the thumb's row, even off to one side, can still get clipped by the
/// thumb's commit fly-out overshoot — putting it in a different SAFE AREA entirely, not just a
/// different X position, is what actually guarantees no overlap at any point of the slide). There is
/// NO Log & Next (that's the thumb) and no Skip button anymore either — skip is now the thumb's left
/// slide, which always acts on the ACTIVE set. Besides the coach cue pill (and the effort dial up
/// top), this is the only other place in the runner that uses Liquid Glass.
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
