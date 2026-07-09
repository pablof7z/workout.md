import SwiftUI

/// TikTok-style horizontal pager with two pages: the Coach screen on the LEFT and the runner on the
/// RIGHT, defaulting to the runner. Swiping RIGHT reveals the Coach (scoped to the current
/// exercise); swiping LEFT returns to the runner.
///
/// Gesture orthogonality: the horizontal page swipe and the runner's vertical set-paging ScrollView
/// operate on perpendicular axes, so they don't deadlock. The effort scale's drag is attached as a
/// `.highPriorityGesture` so dragging the knob wins over the page swipe.
struct SessionView: View {
    @Environment(WorkoutSession.self) private var session
    var onFinish: (SessionSummary) -> Void

    /// 0 = Coach (left), 1 = Runner (right). Default to the runner.
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            CoachView(onBackToRunner: {
                withAnimation { page = 1 }
            })
            .tag(0)

            RunnerView(onFinish: onFinish)
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
    }
}
