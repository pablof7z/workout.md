import SwiftUI

/// What the one-thumb gesture bar resolved a release to. `RunnerView` owns what each outcome
/// actually DOES (session mutation + page animation) — this view only reports the pure gesture
/// result plus the live vertical drag amount while it's in progress.
enum GestureOutcome {
    /// dx past the right threshold: log the active set as done and advance.
    case done
    /// dx past the left threshold: skip the active set and advance.
    case skip
    /// Small |dx|, dy past the up threshold: page the VIEW forward only — nothing logged.
    case peekForward
    /// Small |dx|, dy past the down threshold (only reachable while previewing): page the VIEW back
    /// toward the active set.
    case peekBackward
    /// Released inside all thresholds: snap back to rest.
    case cancel
}

/// The floating glass control cluster docked to the bottom safe area. After the gesture rework this
/// is a single round **thumb** on a track ("the gesture bar") that replaces both the old swipe-down
/// paging AND the Skip button — see `GestureBar` below for the drag mechanics. The small icon-only
/// effort button (`EffortControl`) still floats here, pinned trailing just above the bar so its tap
/// target never overlaps the thumb's horizontal travel.
struct ControlsView: View {
    @Environment(WorkoutSession.self) private var session
    /// The step the pager is currently DISPLAYING (`session.viewStep`) — the effort dial rates
    /// whatever's on screen, independent of which set is next to log.
    let viewStep: WorkoutStep
    let isLast: Bool
    /// True while a commit/peek snap animation is in flight — the thumb ignores new touches so a
    /// second drag can't stack on top of an in-progress page transition.
    let isBusy: Bool
    /// Live vertical translation (points) reported continuously while dragging, so `RunnerView` can
    /// move the page stack in lockstep with the finger.
    var onDragChanged: (CGFloat) -> Void
    /// The resolved outcome on release.
    var onCommit: (GestureOutcome) -> Void

    @State private var effortExpanded = false

    var body: some View {
        VStack(spacing: 10) {
            if case .set = viewStep.page {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    EffortControl(committed: session.rpe[viewStep.id], expanded: $effortExpanded) { value in
                        session.setEffort(value, for: viewStep.id)
                    }
                }
            }

            GestureBar(isLast: isLast, isBusy: isBusy, onDragChanged: onDragChanged, onCommit: onCommit)

            Text("↑ peek  ·  ↗ done  ·  ↖ skip")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 20)
    }
}

/// The one-thumb gesture bar: a round glass thumb centered on a track, with faint "✕ Skip" / "Done
/// ✓" zone hints. A single `DragGesture` on the thumb drives both axes at once:
///
/// - Horizontal moves the thumb along the track; past ±`armThreshold` it "arms" DONE (green,
///   checkmark) or SKIP (amber, ✕), with a haptic tap the moment it arms plus a light ramp as the
///   finger approaches the threshold.
/// - Vertical is purely reported upward via `onDragChanged` — `RunnerView` uses it to page the
///   content stack behind the bar; this view has no opinion on what's on screen.
///
/// On release, `resolveOutcome` classifies the final translation into one `GestureOutcome` and hands
/// it to the parent; this view only owns its own thumb's fly-out/spring-back animation.
private struct GestureBar: View {
    let isLast: Bool
    let isBusy: Bool
    var onDragChanged: (CGFloat) -> Void
    var onCommit: (GestureOutcome) -> Void

    /// Horizontal drag distance driving the thumb's position (and, past threshold, its armed
    /// state). Distinct from the *reported* dy, which this view never stores — `RunnerView` is the
    /// source of truth for the vertical page offset.
    @State private var dx: CGFloat = 0
    @State private var armed: Armed = .none
    /// Discrete ramp tier (0...4) so the approach haptic fires once per tier crossed rather than
    /// once per pixel.
    @State private var hapticTier: Int = 0

    private enum Armed { case none, done, skip }

    private let armThreshold: CGFloat = 68
    private let peekThreshold: CGFloat = 68
    private let maxThumbTravel: CGFloat = 120
    private let thumbSize: CGFloat = 64
    private let trackHeight: CGFloat = 72

    var body: some View {
        ZStack {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: trackHeight / 2))

            fills

            HStack {
                zoneLabel("✕ Skip", color: .orange)
                Spacer(minLength: 0)
                zoneLabel("Done ✓", color: .green)
            }
            .padding(.horizontal, 26)

            thumb
                .offset(x: dx)
                .allowsHitTesting(!isBusy)
                .gesture(dragGesture)
        }
        .frame(height: trackHeight)
    }

    private var fills: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                LinearGradient(colors: [.orange.opacity(0.38), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.6)
                    .opacity(max(0, min(1, -dx / armThreshold)))
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .green.opacity(0.42)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.6)
                    .opacity(max(0, min(1, dx / armThreshold)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: trackHeight / 2))
        .allowsHitTesting(false)
    }

    private func zoneLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(color.opacity(0.9))
            .allowsHitTesting(false)
    }

    private var thumb: some View {
        Circle()
            .fill(.clear)
            .frame(width: thumbSize, height: thumbSize)
            .glassEffect(
                armed == .none
                    ? .regular.interactive()
                    : .regular.tint(armed == .done ? Color.green.opacity(0.85) : Color.orange.opacity(0.8)).interactive(),
                in: .circle
            )
            .overlay {
                Image(systemName: thumbIcon)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel("Gesture control")
            .accessibilityHint("Drag right to mark done, left to skip, up to preview the next set")
    }

    private var thumbIcon: String {
        switch armed {
        case .done: return "checkmark"
        case .skip: return "xmark"
        case .none: return "arrow.up"
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dx = max(-maxThumbTravel, min(maxThumbTravel, value.translation.width))
                onDragChanged(value.translation.height)
                updateArmed(rawDX: value.translation.width)
            }
            .onEnded { value in
                let outcome = resolveOutcome(dx: value.translation.width, dy: value.translation.height)
                onCommit(outcome)
                resetVisualState(for: outcome)
            }
    }

    private func updateArmed(rawDX: CGFloat) {
        let newArmed: Armed
        if rawDX > armThreshold { newArmed = .done }
        else if rawDX < -armThreshold { newArmed = .skip }
        else { newArmed = .none }

        if newArmed != armed {
            armed = newArmed
            if newArmed != .none {
                Haptics.impact(.rigid)
                hapticTier = 4
            }
            return
        }
        guard newArmed == .none else { return }
        // Ramp a light tap as the finger approaches the threshold, one tick per quartile.
        let progress = min(1, abs(rawDX) / armThreshold)
        let tier = Int(progress * 4)
        if tier != hapticTier {
            hapticTier = tier
            if tier > 0 { Haptics.impact(.light) }
        }
    }

    private func resolveOutcome(dx: CGFloat, dy: CGFloat) -> GestureOutcome {
        if dx > armThreshold { return .done }
        if dx < -armThreshold { return .skip }
        if dy < -peekThreshold { return .peekForward }
        if dy > peekThreshold { return .peekBackward }
        return .cancel
    }

    private func resetVisualState(for outcome: GestureOutcome) {
        switch outcome {
        case .done, .skip:
            withAnimation(.easeOut(duration: 0.2)) {
                dx = outcome == .done ? maxThumbTravel + 40 : -(maxThumbTravel + 40)
            }
            Task {
                try? await Task.sleep(nanoseconds: 260_000_000)
                dx = 0
                armed = .none
                hapticTier = 0
            }
        case .peekForward, .peekBackward, .cancel:
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
                dx = 0
            }
            armed = .none
            hapticTier = 0
        }
    }
}
