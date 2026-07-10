import SwiftUI

/// The hero of the app: a full-screen vertical pager where each page is exactly one set (or a
/// rest beat). It reads its steps and position from the shared `WorkoutSession`, which tracks TWO
/// pointers (see `Models.swift`):
/// - `currentStepID` (ACTIVE) — the next set to log. Only a DONE/SKIP commit on the gesture bar
///   advances it.
/// - `viewStepID` (VIEW) — the step currently on screen. A pure-vertical PEEK drag advances this
///   alone, letting the athlete browse ahead without logging anything.
///
/// Layout contract (load-bearing):
/// - The pager fills the ENTIRE device height via `.ignoresSafeArea()`. Unlike the previous
///   `ScrollView`-based pager, paging is now driven entirely by hand: a `ZStack` renders the
///   current and next/previous `StepPageView`s offset by the gesture bar's live drag translation,
///   snapped with `withAnimation` on release. This is required because a single `DragGesture`
///   living on the bottom gesture bar's thumb (see `ControlsView.GestureBar`) must drive BOTH the
///   page transform and the thumb's own horizontal DONE/SKIP arming — a plain paging `ScrollView`
///   has no hook for that.
/// - The floating glass controls float as `.overlay`s over the pager (never `.safeAreaInset`,
///   which would shrink the container and break the full-bleed page sizing).
///
/// Advancing between sets is the one-thumb gesture bar — there is no Skip button and no swipe-down
/// paging gesture on the content itself (the whole screen used to be swipeable; now only the thumb
/// is, so the reps/weight +/- taps and the horizontal Coach-screen swipe in `SessionView` are safe).
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

    /// Which neighbor is currently paired with the view step in the pager `ZStack`, decided the
    /// moment a drag's vertical component first becomes meaningful (see `handleDragChanged`) and
    /// held for the rest of that drag so the two rendered pages don't flicker mid-gesture.
    private enum PageDirection { case none, forward, backward }

    /// Live vertical translation (points) reported by the gesture bar's thumb, clamped to the
    /// direction/limit rules in `handleDragChanged`. Applied as the pager `ZStack`'s offset.
    @State private var dragDY: CGFloat = 0
    @State private var pageDirection: PageDirection = .none
    /// True while a commit/peek snap animation is in flight — the gesture bar disables its thumb
    /// for the duration so a second drag can't interrupt an in-progress page transition.
    @State private var isBusy = false
    @State private var peekChipVisible = false

    var body: some View {
        @Bindable var session = session

        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let pageHeight = proxy.size.height

            pagerStack(pageHeight: pageHeight, safeTop: safeTop, safeBottom: safeBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        if let view = viewStep {
                            TopContextStrip(step: view, stepIndex: viewIndex, totalSteps: session.steps.count) {
                                showingList = true
                            }
                        }
                        if peekChipVisible {
                            PeekChip()
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.top, TopStripMetrics.topOffset)
                    .animation(.easeInOut(duration: 0.2), value: peekChipVisible)
                }
                .overlay(alignment: .leading) {
                    CoachEdgeHint()
                        .padding(.leading, 4)
                }
                .overlay(alignment: .bottom) {
                    if let active = activeStep {
                        ControlsView(
                            viewStep: viewStep ?? active,
                            isLast: isLastActiveStep,
                            isBusy: isBusy,
                            onDragChanged: { dy in handleDragChanged(dy, pageHeight: pageHeight) },
                            onCommit: { outcome in handleCommit(outcome, pageHeight: pageHeight) }
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
            if session.viewStepID == nil {
                session.viewStepID = session.currentStepID
            }
        }
        .onChange(of: session.isPreviewing) { _, previewing in
            peekChipVisible = previewing
        }
        .sheet(isPresented: $showingList) {
            WorkoutListView(
                workoutName: session.activePlan?.name ?? "Workout",
                steps: session.steps,
                currentID: session.viewStepID
            ) { id in
                showingList = false
                withAnimation(.easeInOut(duration: 0.35)) {
                    session.currentStepID = id
                    session.viewStepID = id
                }
            }
        }
    }

    // MARK: Pager

    @ViewBuilder
    private func pagerStack(pageHeight: CGFloat, safeTop: CGFloat, safeBottom: CGFloat) -> some View {
        let idx = viewIndex
        ZStack(alignment: .top) {
            switch pageDirection {
            case .forward:
                page(at: idx, safeTop: safeTop, safeBottom: safeBottom, height: pageHeight)
                    .offset(y: dragDY)
                if idx + 1 < session.steps.count {
                    page(at: idx + 1, safeTop: safeTop, safeBottom: safeBottom, height: pageHeight)
                        .offset(y: dragDY + pageHeight)
                }
            case .backward:
                if idx - 1 >= 0 {
                    page(at: idx - 1, safeTop: safeTop, safeBottom: safeBottom, height: pageHeight)
                        .offset(y: dragDY - pageHeight)
                }
                page(at: idx, safeTop: safeTop, safeBottom: safeBottom, height: pageHeight)
                    .offset(y: dragDY)
            case .none:
                page(at: idx, safeTop: safeTop, safeBottom: safeBottom, height: pageHeight)
            }
        }
    }

    @ViewBuilder
    private func page(at idx: Int, safeTop: CGFloat, safeBottom: CGFloat, height: CGFloat) -> some View {
        if idx >= 0, idx < session.steps.count {
            StepPageView(step: session.steps[idx], topInset: safeTop, bottomInset: safeBottom)
                .frame(height: height)
                .id(session.steps[idx].id)
        }
    }

    // MARK: Gesture wiring

    /// Called continuously while dragging the thumb. Latches a page direction the first time the
    /// vertical component becomes meaningful, then clamps the live offset: forward paging rubber-
    /// bands to a small nudge at the last step (nothing to page into); backward paging is only
    /// reachable while previewing, and rubber-bands once the view is back at the active step.
    private func handleDragChanged(_ dy: CGFloat, pageHeight: CGFloat) {
        if pageDirection == .none {
            if dy < -2 {
                pageDirection = .forward
            } else if dy > 2, session.isPreviewing {
                pageDirection = .backward
            }
        }

        switch pageDirection {
        case .forward:
            let hasNext = viewIndex < session.steps.count - 1
            let limit: CGFloat = hasNext ? -pageHeight : -40
            dragDY = min(0, max(dy, limit))
        case .backward:
            let hasPrev = session.isPreviewing
            let limit: CGFloat = hasPrev ? pageHeight : 40
            dragDY = max(0, min(dy, limit))
        case .none:
            dragDY = 0
        }
    }

    /// Called once on release with the gesture bar's resolved outcome. Owns the actual session
    /// mutation (log/skip/peek) and the page-stack snap animation; `ControlsView.GestureBar` only
    /// animates its own thumb.
    private func handleCommit(_ outcome: GestureOutcome, pageHeight: CGFloat) {
        switch outcome {
        case .done:
            guard let active = activeStep else { return snapBack() }
            Haptics.success()
            let wasLast = isLastActiveStep
            commitAdvance(pageHeight: pageHeight) {
                session.complete(stepID: active.id)
                if wasLast {
                    onFinish(session.buildSummary())
                } else {
                    session.advanceActive()
                }
            }

        case .skip:
            guard let active = activeStep else { return snapBack() }
            Haptics.impact(.light)
            let wasLast = isLastActiveStep
            commitAdvance(pageHeight: pageHeight) {
                session.skip(stepID: active.id)
                if wasLast {
                    onFinish(session.buildSummary())
                } else {
                    session.advanceActive()
                }
            }

        case .peekForward:
            guard pageDirection == .forward, viewIndex < session.steps.count - 1 else { return snapBack() }
            Haptics.selection()
            commitAdvance(pageHeight: pageHeight) {
                session.peekForward()
            }

        case .peekBackward:
            guard pageDirection == .backward, session.isPreviewing else { return snapBack() }
            Haptics.selection()
            commitAdvance(pageHeight: pageHeight) {
                session.peekBackward()
            }

        case .cancel:
            snapBack()
        }
    }

    /// Slides the page stack fully to the next/previous position, then — once off-screen — performs
    /// `mutate` (which moves the session pointer(s)) and resets the stack instantly with no
    /// animation, exactly like a native paging scroll view's snap. Mirrors the reference mock's
    /// "animate the transform, then swap content and zero the transform" trick.
    private func commitAdvance(pageHeight: CGFloat, mutate: @escaping () -> Void) {
        isBusy = true
        let target: CGFloat = pageDirection == .backward ? pageHeight : -pageHeight
        withAnimation(.easeInOut(duration: 0.32)) {
            dragDY = target
        }
        Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            mutate()
            dragDY = 0
            pageDirection = .none
            isBusy = false
        }
    }

    private func snapBack() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            dragDY = 0
        }
        Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            pageDirection = .none
        }
    }

    // MARK: Lookups

    private var activeIndex: Int {
        session.currentIndex ?? 0
    }

    private var activeStep: WorkoutStep? {
        session.currentStep ?? session.steps.first
    }

    private var viewIndex: Int {
        session.viewIndex ?? activeIndex
    }

    private var viewStep: WorkoutStep? {
        session.viewStep ?? activeStep
    }

    private var isLastActiveStep: Bool {
        activeIndex == session.steps.count - 1
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

/// Shown while the view has paged ahead of the active set without a DONE/SKIP commit — a reminder
/// that browsing ahead doesn't log anything.
private struct PeekChip: View {
    var body: some View {
        Text("Previewing — not logged")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .accessibilityLabel("Previewing, not logged")
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
