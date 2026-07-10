import SwiftUI
import Combine
import UIKit

/// The single most important screen in the app: one page = one set. Full-bleed background,
/// big calm typography, a quiet coach cue, and — inside a group — a round counter and mini-map.
///
/// Also hosts the done/skip/pending gesture: `DoneSkipThumb` anchors a round thumb near the bottom
/// of THIS page (so it scrolls with the paging content — see `RunnerView`'s guardrail against a
/// fixed overlay pager), rendering and mutating THIS set's own `SetPageInfo.state` — every page's
/// thumb is interactive, always, regardless of whether the pager happens to be sitting on it.
struct StepPageView: View {
    let step: WorkoutStep
    /// Safe-area insets passed down from the runner (the paging ScrollView ignores the safe area,
    /// so pages must reserve this space themselves).
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    /// The floating `TopContextStrip` pill's rendered geometry (see `RunnerView.TopStripMetrics`):
    /// its 6pt offset from the safe area + its ~34pt capsule height + 16pt of clearance, so page
    /// content (the overline, the mini-map row) never collides with the pill sitting above it.
    private var topReserve: CGFloat { topInset + RunnerView.TopStripMetrics.totalReserve }
    /// Reserves space for the 60pt round done/skip thumb (see `DoneSkipThumb`) plus the 10pt gap
    /// `RunnerView`'s `ControlsView` overlay adds above the safe area (60 + 10 = 70), plus clearance
    /// so hero content never touches it. The effort dial lives in its own top-trailing overlay now
    /// (see `RunnerView`), not this row, so it no longer factors into this reserve.
    private var bottomReserve: CGFloat { bottomInset + 92 }

    var body: some View {
        ZStack {
            BackgroundView(moodKey: step.moodKey)

            switch step.page {
            case .set(let info):
                setContent(info)
            case .rest(let info):
                restContent(info)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .bottom) {
            if case .set(let info) = step.page {
                SetGestureLayer(step: step, state: info.state)
                    .padding(.bottom, bottomInset + 14)
            }
        }
    }

    // MARK: Set page

    @ViewBuilder
    private func setContent(_ info: SetPageInfo) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            overline(for: info)

            if let miniMap = info.miniMap {
                MiniMapRow(items: miniMap)
            }

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 12) {
                // No DONE/SKIPPED badge here — the set's status is rendered ONLY by its slider
                // (`DoneSkipThumb`, bottom of this page), which is always interactive and always
                // showing that set's true state.
                Text(info.exercise.name)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text("Set \(info.setNumber) of \(info.totalSets)")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))

                if case .timed(let seconds) = info.exercise.target {
                    TimedHeroView(totalSeconds: seconds)
                        .padding(.top, 6)
                } else {
                    // Always editable, even for a set already marked done or skipped — the athlete
                    // can page back to any set and fix its reps/weight after the fact.
                    FloatingTargetRows(stepID: step.id)
                        .padding(.top, 6)
                }
            }
            .accessibilityElement(children: .combine)

            CoachCueView(text: info.exercise.cue)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .padding(.top, topReserve)
        .padding(.bottom, bottomReserve)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Only shows round context (round number isn't on the floating `TopContextStrip` pill). The
    /// block/group name itself is already in that pill, so it's omitted here to avoid the page
    /// reading as duplicated/cluttered right under it.
    @ViewBuilder
    private func overline(for info: SetPageInfo) -> some View {
        if let round = info.round, let totalRounds = info.totalRounds {
            Text("ROUND \(round) OF \(totalRounds)")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: Rest page

    @ViewBuilder
    private func restContent(_ info: RestPageInfo) -> some View {
        VStack(spacing: 18) {
            Spacer()

            Text("REST")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))

            RestCountdownText(seconds: info.seconds)

            Text("After round \(info.afterRound) of \(info.totalRounds)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                Text("Next: \(info.nextUpName)")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 28)
        .padding(.top, topReserve)
        .padding(.bottom, bottomReserve)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Done / Skip gesture (rides the paging content, one instance per page)

/// Hosts THIS page's thumb, wiring its commits back to the shared session by `step.id`. Every page
/// gets one of these — there's no "active vs. previewing" branch anymore: whichever set you're
/// looking at, its thumb is live and reflects that set's own `state`.
private struct SetGestureLayer: View {
    @Environment(WorkoutSession.self) private var session
    let step: WorkoutStep
    let state: SetState

    var body: some View {
        DoneSkipThumb(state: state) { newState in
            session.setState(newState, for: step.id)
            switch newState {
            case .done: Haptics.success()
            case .skipped: Haptics.impact(.light)
            case .pending: Haptics.selection()
            }
        }
    }
}

/// The one interactive control in the runner besides the effort dial: a round glass thumb, with NO
/// track, NO labels, NO container behind it — just the circle. It is a PERSISTENT 3-state control,
/// live on every page, always: it renders `state` at rest (`.done` sits toward the right in green
/// with a checkmark, `.skipped` toward the left in amber/orange with an ✕, `.pending` centered and
/// neutral) and lets you slide it into any of the three states from wherever it currently rests —
/// right toward done, left toward skipped, back toward the middle to clear it to pending — whether
/// this page is "current" or one you've paged back to hours later to fix the weight.
///
/// The `DragGesture` is attached with `.simultaneousGesture`, never `.gesture` — that's load-bearing.
/// `.gesture` lets a child's recognizer win exclusively over an ancestor's (which is how buttons work
/// inside a `ScrollView` without also scrolling it), but here the ancestor recognizer we must NOT
/// steal from is the native paging `ScrollView` itself. `.simultaneousGesture` runs both recognizers
/// concurrently, and this view separately keys off `axis` (locked in once the drag's translation is
/// unambiguously horizontal- vs. vertical-dominant, past `axisLockDistance`) to decide whether it has
/// any opinion at all: a vertical-dominant drag — including one that starts right on top of the
/// thumb — never moves it and fires no haptic, so the page behind it pages away exactly as if the
/// thumb weren't there. Verified on-device: vertical swipes starting on the thumb still page.
private struct DoneSkipThumb: View {
    /// The set's committed state — the source of truth this thumb rests at when not being dragged.
    let state: SetState
    /// Fired once a drag crosses a threshold into a DIFFERENT state than `state` and is released.
    var onCommit: (SetState) -> Void

    private enum DragAxis { case horizontal, vertical }

    /// Additional horizontal offset from `state`'s resting position, live only while a horizontal
    /// drag is in progress; snaps back to 0 once released (the new resting position then comes from
    /// the updated `state` prop itself, not from this).
    @State private var dragTranslation: CGFloat = 0
    @State private var axis: DragAxis?
    /// The state the thumb is provisionally previewing mid-drag (nil = just showing `state`).
    @State private var provisional: SetState?
    @State private var hapticTier = 0
    @State private var isSettling = false

    private let armThreshold: CGFloat = 64
    private let maxTravel: CGFloat = 92
    /// How far off-center the thumb rests once committed to `.done`/`.skipped` — short of `maxTravel`
    /// so there's still plenty of room to drag further, and short of `armThreshold` so resting there
    /// doesn't read as "still mid-drag".
    private let restOffset: CGFloat = 40
    private let axisLockDistance: CGFloat = 8
    private let size: CGFloat = 60

    private var displayState: SetState { provisional ?? state }

    private func restingOffset(for value: SetState) -> CGFloat {
        switch value {
        case .pending: return 0
        case .done: return restOffset
        case .skipped: return -restOffset
        }
    }

    private var offset: CGFloat {
        restingOffset(for: state) + dragTranslation
    }

    var body: some View {
        Circle()
            .fill(.clear)
            .frame(width: size, height: size)
            .glassEffect(glassStyle, in: .circle)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .offset(x: offset)
            .allowsHitTesting(!isSettling)
            .simultaneousGesture(drag)
            .accessibilityLabel("Set status: \(accessibilityStateName)")
            .accessibilityHint("Drag right to mark done, left to mark skipped, center for pending")
    }

    private var glassStyle: Glass {
        switch displayState {
        case .pending: return .regular.interactive()
        case .done: return .regular.tint(Color.green.opacity(0.85)).interactive()
        case .skipped: return .regular.tint(Color.orange.opacity(0.85)).interactive()
        }
    }

    private var icon: String {
        switch displayState {
        case .pending: return "arrow.left.and.right"
        case .done: return "checkmark"
        case .skipped: return "xmark"
        }
    }

    private var accessibilityStateName: String {
        switch state {
        case .pending: return "pending"
        case .done: return "done"
        case .skipped: return "skipped"
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard !isSettling else { return }
                let w = value.translation.width
                let h = value.translation.height
                if axis == nil, max(abs(w), abs(h)) > axisLockDistance {
                    axis = abs(w) > abs(h) ? .horizontal : .vertical
                }
                // Vertical-dominant (or not yet locked): don't move the thumb or fight the native
                // scroll at all — the ScrollView's own simultaneous recognizer handles paging.
                guard axis == .horizontal else { return }
                let raw = restingOffset(for: state) + w
                let clamped = max(-maxTravel, min(maxTravel, raw))
                dragTranslation = clamped - restingOffset(for: state)
                updateRamp(position: clamped)
            }
            .onEnded { _ in
                defer { axis = nil }
                guard axis == .horizontal, !isSettling else { return }
                resolve()
            }
    }

    /// Ramps a real `UIImpactFeedbackGenerator` as the thumb approaches `armThreshold` (one tap per
    /// fifth of the way there), then morphs the glyph the moment it arms.
    private func updateRamp(position: CGFloat) {
        let progress = min(1, abs(position) / armThreshold)
        let tier = Int(progress * 5)
        if tier != hapticTier {
            hapticTier = tier
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: max(0.15, progress))
        }
        let newProvisional: SetState = position > armThreshold ? .done : (position < -armThreshold ? .skipped : .pending)
        if newProvisional != displayState {
            provisional = newProvisional
        }
    }

    private func resolve() {
        let position = max(-maxTravel, min(maxTravel, restingOffset(for: state) + dragTranslation))
        let newState: SetState = position > armThreshold ? .done : (position < -armThreshold ? .skipped : .pending)
        let changed = newState != state
        isSettling = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
            dragTranslation = 0
            provisional = nil
            if changed { onCommit(newState) }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            hapticTier = 0
            isSettling = false
        }
    }
}

/// The set's target, as two always-visible floating lines — reps, then weight (when the exercise
/// tracks one) — each flanked by minus/plus glyph buttons. No tap-to-reveal gate and no glass
/// container: like the exercise name and set line above it, each row floats as plain text directly
/// over the full-bleed background. Reads and mutates the shared `WorkoutSession` by `stepID` (rather
/// than trusting the `SetPageInfo` snapshot passed down from `StepPageView`) so a − / + tap here is
/// reflected immediately, matching the pattern the old bottom-toolbar reps stepper used. Edits land
/// in the same live `steps` array the coach's `adjust_set` tool mutates, so they persist into the
/// logged "actual" set once the session finishes.
private struct FloatingTargetRows: View {
    @Environment(WorkoutSession.self) private var session
    let stepID: WorkoutStep.ID

    private var target: SetTarget {
        guard let idx = session.steps.firstIndex(where: { $0.id == stepID }),
              case .set(let info) = session.steps[idx].page else { return .reps(count: 0, weight: nil) }
        return info.exercise.target
    }

    private var reps: Int {
        if case .reps(let count, _) = target { return count }
        return 0
    }

    private var weight: Double? {
        target.weight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FloatingStepRow(value: reps, unit: "reps") { delta in
                Haptics.selection()
                session.adjustReps(forStepID: stepID, delta: delta)
            }

            if weight != nil {
                FloatingStepRow(value: Int(weight ?? 0), unit: "lb", step: 5) { delta in
                    Haptics.selection()
                    session.adjustWeight(forStepID: stepID, delta: Double(delta))
                }
            }
        }
        // Always interactive — a set already marked done or skipped is still fully editable, so the
        // athlete can page back and fix the weight/reps after the fact without unmarking anything.
        .accessibilityElement(children: .contain)
    }
}

/// One floating "− value unit +" line. Minimal, ungrouped glyph buttons (large ~46pt tap targets,
/// light-weight glyph, subdued color) flank a big bold value — no glass, no pill background.
private struct FloatingStepRow: View {
    let value: Int
    let unit: String
    var step: Int = 1
    var onAdjust: (Int) -> Void

    var body: some View {
        HStack(spacing: 22) {
            GlyphButton(symbol: "minus", label: "Decrease \(unit)") { onAdjust(-step) }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(value)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                Text(unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .frame(minWidth: 132, alignment: .leading)
            .animation(.snappy, value: value)

            GlyphButton(symbol: "plus", label: "Increase \(unit)") { onAdjust(step) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value) \(unit)")
    }
}

/// A minimal, ungrouped glyph button — light-weight glyph at low-opacity white, no background.
/// ~46pt tappable target even though the glyph itself reads much smaller, per HIG touch guidance.
private struct GlyphButton: View {
    let symbol: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Live countdown hero for a timed set (e.g. Plank 45 sec). Shows the duration with a glass Start
/// button; tapping Start runs a real 1-per-tick countdown with a circular progress ring that
/// depletes as time runs out. Tapping the ring toggles pause/resume, and a small reset restarts.
/// At zero it fires a success haptic and shows a quiet "Swipe down for next" hint (advancing is a
/// swipe on the pager — there is no Log & Next). The countdown is driven by a Combine timer that
/// only advances while `isRunning`, and it stops itself in `onDisappear`, so it never keeps running
/// once the page scrolls away.
private struct TimedHeroView: View {
    let totalSeconds: Int

    @State private var remaining: Double
    @State private var isRunning = false
    @State private var hasStarted = false
    @State private var finished = false

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(totalSeconds: Int) {
        self.totalSeconds = totalSeconds
        _remaining = State(initialValue: Double(totalSeconds))
    }

    private var progress: Double {
        totalSeconds > 0 ? max(0, min(1, remaining / Double(totalSeconds))) : 0
    }
    private var displaySeconds: Int { Int(ceil(remaining)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 22) {
                ring

                if !hasStarted {
                    Button(action: start) {
                        Label("Start", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .frame(height: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.indigo)
                    .accessibilityLabel("Start timer")
                } else {
                    VStack(spacing: 10) {
                        Text(finished ? "Done" : (isRunning ? "Running" : "Paused"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(finished ? .green : .white.opacity(0.7))
                        Button(action: reset) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 50, height: 50)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Reset timer")
                    }
                }

                Spacer(minLength: 0)
            }

            if finished {
                Label("Swipe down for next", systemImage: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .onReceive(tick) { _ in
            guard isRunning else { return }
            remaining = max(0, remaining - 0.05)
            if remaining <= 0 { complete() }
        }
        .onDisappear { isRunning = false }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    finished ? Color.green : Color.mint,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.06), value: progress)

            VStack(spacing: -2) {
                Text("\(displaySeconds)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("sec")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 132, height: 132)
        .contentShape(Circle())
        .onTapGesture { if hasStarted { toggle() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer, \(displaySeconds) seconds remaining")
        .accessibilityAddTraits(.isButton)
    }

    private func start() {
        Haptics.impact(.light)
        finished = false
        hasStarted = true
        isRunning = true
    }

    private func toggle() {
        guard !finished else { return }
        Haptics.selection()
        isRunning.toggle()
    }

    private func reset() {
        Haptics.selection()
        remaining = Double(totalSeconds)
        isRunning = false
        hasStarted = false
        finished = false
    }

    private func complete() {
        remaining = 0
        isRunning = false
        withAnimation(.easeInOut) { finished = true }
        Haptics.success()
    }
}

/// Live rest countdown ring, visually matching `TimedHeroView`'s ring (same 132pt size, 8pt stroke,
/// mint→green completion color, monospaced-digit display). Unlike `TimedHeroView`, rest is passive:
/// there's no "Start" tap, the countdown runs the moment the page appears. Driven by the same
/// 0.05s Combine timer pattern, it fires a success haptic and flips to a "done" ring at zero, and
/// it stops itself in `onDisappear` so it never keeps running once the page scrolls away.
private struct RestCountdownText: View {
    let seconds: Int

    @State private var remaining: Double
    @State private var isRunning = true
    @State private var finished = false

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(seconds: Int) {
        self.seconds = seconds
        _remaining = State(initialValue: Double(seconds))
    }

    private var progress: Double {
        seconds > 0 ? max(0, min(1, remaining / Double(seconds))) : 0
    }
    private var displaySeconds: Int { Int(ceil(remaining)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    finished ? Color.green : Color.mint,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.06), value: progress)

            VStack(spacing: -2) {
                Text("\(displaySeconds)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(finished ? "done" : "sec")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 132, height: 132)
        .onReceive(tick) { _ in
            guard isRunning else { return }
            remaining = max(0, remaining - 0.05)
            if remaining <= 0 { complete() }
        }
        .onDisappear { isRunning = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(finished ? "Rest complete" : "\(displaySeconds) seconds rest remaining")
    }

    private func complete() {
        remaining = 0
        isRunning = false
        withAnimation(.easeInOut) { finished = true }
        Haptics.success()
    }
}

/// Quiet coach line, presented as a small glass pill — never a chat bubble.
private struct CoachCueView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.bubble")
                .font(.subheadline)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .frame(maxWidth: 340, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach cue: \(text)")
    }
}

/// Inline "A1 Incline DB · ▶ A2 Barbell Row · A3 ..." style mini-map for a superset/circuit group,
/// highlighting the movement that's currently up.
private struct MiniMapRow: View {
    let items: [MiniMapItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        if item.isCurrent {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                        }
                        Text("\(item.shortLabel) \(item.name)")
                            .lineLimit(1)
                    }
                    .font(.caption.weight(item.isCurrent ? .semibold : .regular))
                    .foregroundStyle(item.isCurrent ? .white : .white.opacity(0.4))

                    if item.id != items.last?.id {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let parts = items.map { item in
            item.isCurrent ? "current, \(item.shortLabel) \(item.name)" : "\(item.shortLabel) \(item.name)"
        }
        return "Movements: " + parts.joined(separator: ", ")
    }
}
