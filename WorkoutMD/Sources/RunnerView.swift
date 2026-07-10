import SwiftUI

/// The hero of the app: a full-screen vertical pager where each page is exactly one set (or a
/// rest beat). It reads its steps and current position from the shared `WorkoutSession`, so edits
/// made on the Coach screen (or by the effort control / reps stepper) reflect on upcoming pages.
///
/// Layout contract (load-bearing):
/// - The paging `ScrollView` spans the ENTIRE device height via `.ignoresSafeArea()`, so the
///   paging container is full-screen and `.containerRelativeFrame([.horizontal, .vertical])` makes
///   each page exactly full-screen (1:1 paging stride, no adjacent-page sliver).
/// - The floating glass controls float as `.overlay`s over the current page (never `.safeAreaInset`,
///   which would shrink the scroll container and break the stride).
///
/// Navigation is completely free: vertical swipe (the native paging) just moves `session.currentStepID`
/// — there's no separate "active" pointer to advance, and no "previewing" state. Each `StepPageView`
/// hosts its own persistent done/skip/pending slider (see `DoneSkipThumb`) that renders and mutates
/// THAT set's own status, independent of the pager's position — so paging away and back always shows
/// the set exactly how you left it, still slidable to any other state.
struct RunnerView: View {
    /// Sizing for the floating `TopContextStrip` pill, shared with `StepPageView` so its `topReserve`
    /// can be derived from the pill's *actual* rendered geometry instead of a guessed constant.
    ///
    /// IMPORTANT: `.overlay(alignment: .top)` on a view that has `.ignoresSafeArea()` still
    /// implicitly offsets the overlay's alignment guide by the safe area — the safe area is NOT
    /// truly ignored for overlay placement, only for the painted content. So the pill's padding
    /// must NOT add `safeTop` again on top of that (verified empirically: adding it double-counts
    /// the inset and pushes the pill roughly `safeTop` pt further down than intended, which is what
    /// caused it to visually collide with page content below even though `topReserve` looked
    /// correct on paper). `topOffset` here is a small *additional* gap beyond the safe area the
    /// overlay already applies on its own.
    ///
    /// `height` is the pill's actual rendered height once `.frame(minHeight: 44)` is applied for
    /// the HIG touch-target minimum. `totalReserve` adds `topOffset` + `height` + 24pt of clearance,
    /// so page content never collides with it.
    enum TopStripMetrics {
        static let topOffset: CGFloat = 8
        static let height: CGFloat = 44
        static let clearance: CGFloat = 24
        static let totalReserve: CGFloat = topOffset + height + clearance // 76
    }

    @Environment(WorkoutSession.self) private var session
    var onFinish: (SessionSummary) -> Void

    @State private var showingList = false

    var body: some View {
        @Bindable var session = session

        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(session.steps) { step in
                        StepPageView(
                            step: step,
                            topInset: safeTop,
                            bottomInset: safeBottom
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(step.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $session.currentStepID)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if let current = currentStep {
                    TopContextStrip(step: current, stepIndex: currentIndex, totalSteps: session.steps.count) {
                        showingList = true
                    }
                    .padding(.top, TopStripMetrics.topOffset)
                }
            }
            .overlay(alignment: .bottom) {
                if currentStep != nil {
                    ControlsView(
                        isLast: isLastStep,
                        onFinish: { onFinish(session.buildSummary()) }
                    )
                    // Same overlay-alignment quirk as the top pill (see `TopStripMetrics`): the
                    // safe area is already implicitly applied to a bottom-aligned overlay, so this
                    // padding must not add `safeBottom` again.
                    .padding(.bottom, 10)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if session.currentStepID == nil {
                session.currentStepID = session.steps.first?.id
            }
        }
        .sheet(isPresented: $showingList) {
            WorkoutListView(
                workoutName: session.activePlan?.name ?? "Workout",
                steps: session.steps,
                currentID: session.currentStepID
            ) { id in
                showingList = false
                withAnimation(.easeInOut(duration: 0.35)) {
                    session.currentStepID = id
                }
            }
        }
    }

    private var currentIndex: Int {
        session.currentIndex ?? 0
    }

    private var currentStep: WorkoutStep? {
        session.currentStep ?? session.steps.first
    }

    private var isLastStep: Bool {
        currentIndex == session.steps.count - 1
    }
}

/// Small floating glass pill pinned to the top safe area showing where you are in the whole
/// session. Tapping it opens the full workout list.
private struct TopContextStrip: View {
    let step: WorkoutStep
    let stepIndex: Int
    let totalSteps: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(step.blockName)
                    .font(.caption.weight(.semibold))
                Text("·")
                    .foregroundStyle(.white.opacity(0.35))
                Text("\(stepIndex + 1)/\(totalSteps)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                Image(systemName: "list.bullet")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        // The capsule's visual height (~34pt, see `TopStripMetrics.height`) is under the 44pt HIG
        // minimum touch target; grow the hit area without growing the visible glass shape.
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("\(step.blockName), step \(stepIndex + 1) of \(totalSteps)")
        .accessibilityHint("Opens the full workout list")
    }
}
