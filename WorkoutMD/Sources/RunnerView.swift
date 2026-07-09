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
/// Advancing between sets is a SWIPE DOWN (the vertical paging) — there is no Log & Next button.
struct RunnerView: View {
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
                        StepPageView(step: step, topInset: safeTop, bottomInset: safeBottom)
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
                    .padding(.top, safeTop + 6)
                }
            }
            .overlay(alignment: .leading) {
                CoachEdgeHint()
                    .padding(.leading, 4)
            }
            .overlay(alignment: .bottom) {
                if let current = currentStep {
                    ControlsView(
                        step: current,
                        isLast: isLastStep,
                        onSkip: skip,
                        onFinish: { onFinish(session.buildSummary()) }
                    )
                    .padding(.bottom, safeBottom + 10)
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
                workoutName: MockWorkout.name,
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

    private func skip() {
        guard let current = currentStep else { return }
        session.skip(stepID: current.id)
        if !isLastStep {
            let next = session.steps[currentIndex + 1]
            withAnimation(.easeInOut(duration: 0.35)) {
                session.currentStepID = next.id
            }
        }
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
        .accessibilityLabel("\(step.blockName), step \(stepIndex + 1) of \(totalSteps)")
        .accessibilityHint("Opens the full workout list")
    }
}

/// A faint leading-edge hint that swiping right reveals the Coach screen. Purely decorative — the
/// actual gesture is handled by the horizontal pager in `SessionView`.
private struct CoachEdgeHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "chevron.left")
                .font(.caption.weight(.bold))
            Text("Coach")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .frame(height: 44)
        }
        .foregroundStyle(.white.opacity(0.35))
        .accessibilityHidden(true)
    }
}
