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
    /// so hero content never touches it. Effort is now reached by tapping the thumb itself (it opens
    /// a transient sheet rather than living in a persistent overlay), so it doesn't factor into this
    /// reserve either.
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
///
/// A horizontal slide-right/slide-left commits `.done`/`.skipped` directly (see `DoneSkipThumb`,
/// which always springs back to center once released — see #2 in `RunnerView`'s doc comment).
/// A plain TAP on the thumb (negligible movement, disambiguated inside `DoneSkipThumb`) instead
/// opens the "How hard was it?" effort prompt (`EffortPromptSheet`); the instant a value is picked
/// there, it's recorded as this set's RPE AND the set is marked `.done` — both paths then auto-
/// advance the pager to the next set via `WorkoutSession.advanceToNextStep(after:)`.
private struct SetGestureLayer: View {
    @Environment(WorkoutSession.self) private var session
    let step: WorkoutStep
    let state: SetState

    @State private var showingEffortPrompt = false

    var body: some View {
        DoneSkipThumb(
            state: state,
            onCommit: { newState in
                session.setState(newState, for: step.id)
                switch newState {
                case .done: Haptics.success()
                case .skipped: Haptics.impact(.light)
                case .pending: Haptics.selection()
                }
                if newState != .pending {
                    session.advanceToNextStep(after: step.id)
                }
            },
            onTapEffort: {
                showingEffortPrompt = true
            },
            rpe: session.rpe[step.id]
        )
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showingEffortPrompt) {
            EffortPromptSheet(current: session.rpe[step.id]) { rpe in
                session.setEffort(rpe, for: step.id)
                session.setState(.done, for: step.id)
                Haptics.success()
                showingEffortPrompt = false
                session.advanceToNextStep(after: step.id)
            }
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
    }
}

/// The one interactive control in the runner, rebuilt to look/behave like iOS's slide-to-power-off:
/// a round glass knob riding snugly inside a glass pill that HUGS it (`trackHeight` = `size` + ~8pt
/// of inset, not a big track around a tiny button). Unlike the previous revision, the drag gesture is
/// attached to the ENTIRE pill (see `dragSurface`), not just the small knob circle — you can grab and
/// drag from anywhere on the track. It is a PERSISTENT 3-state control, live on every page, always —
/// it never rests off-center: whatever `state` is, the knob always shows at dead-center, and that
/// state is conveyed purely by the knob's icon + tint (`.pending` a minimal neutral grip handle —
/// deliberately NOT a left-right-arrows glyph, which read as an instructional label — `.done` green
/// checkmark, `.skipped` amber ✕). Sliding it past `armThreshold` either side commits a new state and
/// springs the knob straight back to center to show it; a plain tap (negligible movement) instead
/// opens the effort prompt via `onTapEffort`.
///
/// A subtle shimmering "slide" hint sits in the track behind the knob (only while `state == .pending`,
/// so it never fights the committed ✓/✕ tint) and fades out the moment a drag starts.
///
/// The track (and the slide travel riding over it) spans roughly 80% of the page's width (read live
/// via the enclosing `GeometryReader`, not a fixed constant) so left = skip / right = done have a
/// long, comfortable throw — previously this travel was a fixed ~184pt, only about a third of most
/// screens.
///
/// The `DragGesture` is attached with `.simultaneousGesture`, never `.gesture` — that's load-bearing.
/// `.gesture` lets a child's recognizer win exclusively over an ancestor's (which is how buttons work
/// inside a `ScrollView` without also scrolling it), but here the ancestor recognizer we must NOT
/// steal from is the native paging `ScrollView` itself. `.simultaneousGesture` runs both recognizers
/// concurrently, and this view separately keys off `axis` (locked in once the drag's translation is
/// unambiguously horizontal- vs. vertical-dominant, past `axisLockDistance`) to decide whether it has
/// any opinion at all: a vertical-dominant drag — including one that starts anywhere on the pill —
/// never moves the knob and fires no haptic, so the page behind it pages away exactly as if the pill
/// weren't there. Verified on-device: vertical swipes starting on the track still page.
///
/// A separate `TapGesture`, also `.simultaneousGesture`, handles the tap-for-effort path: SwiftUI's
/// tap recognizer only succeeds within a small system movement tolerance, so a real committing drag
/// (which must travel well past `armThreshold` to do anything) never also fires it, and a genuine
/// tap never gets swallowed by the 2pt-`minimumDistance` `DragGesture` either (that one simply never
/// arms `axis` for movement that small, so its `onEnded` no-ops).
private struct DoneSkipThumb: View {
    /// The set's committed state — the source of truth this thumb always shows once at rest.
    let state: SetState
    /// Fired once a drag crosses `armThreshold` into a DIFFERENT state than `state` and is released.
    var onCommit: (SetState) -> Void
    /// Fired on a plain tap (as opposed to a horizontal drag) — opens the effort prompt.
    var onTapEffort: () -> Void
    /// The set's committed RPE (6–10) if it's been rated — shown as a small badge on the ✓ (done) knob.
    var rpe: Double? = nil

    private enum DragAxis { case horizontal, vertical }

    /// Live horizontal offset from center while a horizontal drag is in progress; always animates
    /// back to 0 once released — the thumb never rests anywhere but dead-center (state is shown by
    /// icon + tint instead, see `knobFillColor`/`icon`).
    @State private var dragTranslation: CGFloat = 0
    @State private var axis: DragAxis?
    /// The state the thumb is provisionally previewing mid-drag (nil = just showing `state`), only
    /// set once the drag has actually crossed `armThreshold` either direction.
    @State private var provisional: SetState?
    @State private var hapticTier = 0
    @State private var isSettling = false
    /// The page's own width, captured from the `GeometryReader` in `body` — `maxTravel`/`armThreshold`
    /// are derived from this fraction rather than a fixed constant, so the slide's travel scales with
    /// the actual screen instead of being a fixed distance that reads as narrow on larger phones.
    @State private var trackWidth: CGFloat = 320

    private let axisLockDistance: CGFloat = 8
    /// Knob diameter — 20% larger than the original 60pt design (72pt), while staying well above
    /// the 44pt HIG minimum tap target.
    private let size: CGFloat = 72
    /// The slide track spans ~80% of the page width.
    private let trackWidthFraction: CGFloat = 0.8
    /// The visible glass pill's height: knob diameter + ~8pt of inset, so the knob sits snug inside
    /// it (slide-to-power-off silhouette) rather than a big track around a tiny button.
    private let trackHeight: CGFloat = 80
    /// Fraction of `maxTravel` a drag must cross to arm a commit — matches the old 64/92 ratio.
    private let armThresholdFraction: CGFloat = 0.68

    private var maxTravel: CGFloat { max(70, trackWidth * trackWidthFraction / 2 - size / 2) }
    private var armThreshold: CGFloat { maxTravel * armThresholdFraction }

    private var displayState: SetState { provisional ?? state }

    /// The shimmering "slide" hint fades out fast once a drag starts moving the knob, and never
    /// shows at all once the set is already committed (so it doesn't fight the ✓/✕ tint at rest).
    private var hintOpacity: Double {
        guard state == .pending else { return 0 }
        return max(0, 1 - Double(abs(dragTranslation)) / 40)
    }

    var body: some View {
        VStack(spacing: 6) {
            effortLabelRow
            GeometryReader { geo in
                dragSurface
                    .frame(width: geo.size.width, height: trackHeight)
                    .onAppear { trackWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in trackWidth = newValue }
            }
            .frame(height: trackHeight)
        }
    }

    /// A small label a few points ABOVE the slider showing the rated effort ("HARD", "VERY HARD", …)
    /// once the set is done + rated — sits in a fixed-height row so the slider never shifts when it
    /// appears/disappears.
    private var effortLabelRow: some View {
        ZStack {
            if displayState == .done, let rpe {
                Text(EffortScale.label(for: rpe).uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(EffortScale.color(for: rpe))
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(height: 18)
    }

    /// The whole pill IS the drag surface — the `DragGesture`/`TapGesture` are attached here, at the
    /// full track's width/height, rather than to the small knob circle, so grabbing anywhere on the
    /// glass pill (not just the ~72pt knob) starts the slide. `.contentShape(Capsule())` makes the
    /// full rounded-rect region hit-testable even though the track itself paints as translucent glass.
    ///
    /// IMPORTANT: the glass track and the solid knob are deliberately NOT siblings inside the same
    /// `GlassEffectContainer` — a `GlassEffectContainer` shares one offscreen compositing pass across
    /// everything inside it so its `.glassEffect()` shapes can morph/blend together, and empirically
    /// that pass was also smearing the plain solid knob `Circle()` into a soft, blurry, low-contrast
    /// blob (confirmed on-device) even though the knob itself declared no `.glassEffect`. The track's
    /// `GlassEffectContainer` below wraps ONLY the capsule, so it has nothing to blend with and stays
    /// a normal frosted pill; the knob is a fully separate sibling layered on top of it in `body`'s
    /// outer `ZStack`, immune to that compositing pass — solid, opaque, crisp in every state.
    private var dragSurface: some View {
        ZStack {
            // Plain, CRISP translucent track — deliberately NOT `.glassEffect`/`GlassEffectContainer`.
            // The iOS 26 Liquid Glass compositing pass was smearing the entire control (track AND the
            // solid knob) into a soft, blurry, low-contrast blob on-device. A hand-drawn frosted capsule
            // (flat translucent fill + hairline stroke) renders sharp at any size with zero blur.
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .frame(width: trackWidth * trackWidthFraction, height: trackHeight)

            hint

            knob
                .offset(x: dragTranslation)
        }
        .frame(width: trackWidth * trackWidthFraction, height: trackHeight)
        .contentShape(Capsule())
        .allowsHitTesting(!isSettling)
        .simultaneousGesture(drag)
        .simultaneousGesture(TapGesture().onEnded { handleTap() })
        .accessibilityLabel("Set status: \(accessibilityStateName)")
        .accessibilityHint("Tap to rate effort. Drag right to mark done, left to mark skipped.")
    }

    /// The knob itself: a CRISP, fully OPAQUE, solid-filled circle in every state, including
    /// `.pending` at rest — deliberately NOT `.glassEffect`/a translucent material (that rendered as
    /// a soft, low-contrast, nearly-invisible blur against the dark background, both from a tinted
    /// glass fill AND from sharing a `GlassEffectContainer` with the track, see `dragSurface`'s doc
    /// comment). Only a small, tight drop shadow gives it lift; the fill is a flat vector color per
    /// state and the ✓/skip glyphs are plain SF Symbols with a flat stroke color — nothing here can
    /// blur or band, and it always reads as an obvious, tappable, sharp knob sitting in the track.
    private var knob: some View {
        Circle()
            .fill(knobFillColor)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 3)
            .overlay {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(iconTint)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    // `.pending` shows a minimal, neutral grip handle — not a direction glyph.
                    pendingGrip
                }
            }
    }

    /// Two subtle vertical bars — a minimal "grip" affordance, like a drag handle, shown only while
    /// the knob is neutral/pending (never overlaid on the ✓/✕ glyphs). Dark-on-light, matching the
    /// light neutral knob fill (see `knobFillColor`).
    private var pendingGrip: some View {
        HStack(spacing: 4) {
            Capsule().fill(Color.black.opacity(0.28)).frame(width: 3, height: 20)
            Capsule().fill(Color.black.opacity(0.28)).frame(width: 3, height: 20)
        }
    }

    /// A quiet shimmering "slide" label sitting in the track behind the knob, like iOS's "slide to
    /// power off" — a moving highlight band sweeps across the text continuously via `TimelineView`,
    /// and the whole label fades out (`hintOpacity`) the moment a drag begins.
    private var hint: some View {
        TimelineView(.animation) { timeline in
            let period = 2.4
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let phase = CGFloat(t) * 2.6 - 0.8 // sweeps roughly -0.8...1.8 across the text
            Text("slide")
                .font(.subheadline.weight(.semibold))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.28), location: phase - 0.35),
                            .init(color: .white.opacity(0.95), location: phase),
                            .init(color: .white.opacity(0.28), location: phase + 0.35),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .frame(width: trackWidth * trackWidthFraction)
        .opacity(hintOpacity)
        .allowsHitTesting(false)
    }

    /// Flat, solid per-state knob fill — a light neutral for `.pending` (grip handle reads dark on
    /// it), a clean pastel green for `.done`, a clean pastel amber for `.skipped`. No gradients-through-
    /// translucency, no material tint: a single opaque color renders sharp at any size.
    private var knobFillColor: Color {
        switch displayState {
        case .pending: return Color.white
        case .done: return Color(red: 0.486, green: 0.894, blue: 0.608)
        case .skipped: return Color(red: 1.0, green: 0.824, blue: 0.478)
        }
    }

    /// The ✓/skip glyph's flat stroke color — dark-on-light to stay legible against the light,
    /// opaque `knobFillColor` (unused for `.pending`, which shows `pendingGrip` instead).
    private var iconTint: Color {
        switch displayState {
        case .done: return Color(red: 0.039, green: 0.490, blue: 0.200)
        case .skipped, .pending: return Color(red: 0.541, green: 0.353, blue: 0.0)
        }
    }

    /// `nil` for `.pending` — rendered as a minimal grip handle instead of a glyph (see `body`),
    /// deliberately NOT the old ↔ left-right-arrows icon, which read as an unwanted instructional
    /// label. While actively being dragged left (`axis == .horizontal`, not yet committed/settled),
    /// `.skipped` previews as a forward/skip glyph rather than the committed ✕ — the moment the drag
    /// resolves (`axis` resets to `nil`, see `resolve()`), it settles into the final ✕ so the at-rest
    /// state always matches how a skipped set reads everywhere else in the app.
    private var icon: String? {
        switch displayState {
        case .pending: return nil
        case .done: return "checkmark"
        case .skipped: return axis == .horizontal ? "forward.fill" : "xmark"
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
                let clamped = max(-maxTravel, min(maxTravel, w))
                dragTranslation = clamped
                updateRamp(position: clamped)
            }
            .onEnded { _ in
                defer { axis = nil }
                guard axis == .horizontal, !isSettling else { return }
                resolve()
            }
    }

    /// A plain tap (no meaningful drag ever recognized) opens the effort prompt.
    private func handleTap() {
        guard !isSettling else { return }
        Haptics.selection()
        onTapEffort()
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
        let newProvisional: SetState? = position > armThreshold ? .done : (position < -armThreshold ? .skipped : nil)
        if newProvisional != provisional {
            provisional = newProvisional
        }
    }

    /// Always springs `dragTranslation` back to 0 (dead-center) regardless of outcome — only the
    /// icon/tint change when a commit happens; the thumb itself never rests off to a side.
    private func resolve() {
        let clamped = max(-maxTravel, min(maxTravel, dragTranslation))
        let newState: SetState? = clamped > armThreshold ? .done : (clamped < -armThreshold ? .skipped : nil)
        isSettling = true
        withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) {
            dragTranslation = 0
            provisional = nil
            if let newState, newState != state { onCommit(newState) }
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
///
/// Tapping the VALUE itself (as opposed to the − / + glyph buttons) instead opens `NumericEntryPopup`
/// — a small sheet with a real numeric keyboard — so the athlete can type an exact value rather than
/// tapping + repeatedly. Both paths (steppers and the popup) funnel through the same
/// `adjustReps`/`adjustWeight` setters on `WorkoutSession`, computing a delta from the typed absolute
/// value, so there's exactly one mutation path per field.
private struct FloatingTargetRows: View {
    @Environment(WorkoutSession.self) private var session
    let stepID: WorkoutStep.ID

    private enum EditingField: Identifiable {
        case reps, weight
        var id: Self { self }
    }

    @State private var editingField: EditingField?

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
        // Centered (rather than leading-aligned) horizontally on the screen — `.frame(maxWidth:
        // .infinity)` stretches this view to the full page width inside `setContent`'s otherwise
        // leading-aligned VStack, then `alignment: .center` centers the rows (and each other, when
        // their widths differ) within that.
        VStack(alignment: .center, spacing: 8) {
            FloatingStepRow(
                displayValue: Double(reps),
                formattedText: "\(reps)",
                unit: "reps",
                onAdjust: { delta in
                    Haptics.selection()
                    session.adjustReps(forStepID: stepID, delta: Int(delta))
                },
                onTapValue: { editingField = .reps }
            )

            if let weight {
                FloatingStepRow(
                    displayValue: weight,
                    formattedText: Self.formatWeight(weight),
                    unit: "lb",
                    step: 5,
                    onAdjust: { delta in
                        Haptics.selection()
                        session.adjustWeight(forStepID: stepID, delta: delta)
                    },
                    onTapValue: { editingField = .weight }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // Always interactive — a set already marked done or skipped is still fully editable, so the
        // athlete can page back and fix the weight/reps after the fact without unmarking anything.
        .accessibilityElement(children: .contain)
        .sheet(item: $editingField) { field in
            switch field {
            case .reps:
                NumericEntryPopup(title: "Reps", initialValue: Double(reps), unit: "reps", allowsDecimal: false) { newValue in
                    let delta = Int(newValue.rounded()) - reps
                    if delta != 0 {
                        Haptics.selection()
                        session.adjustReps(forStepID: stepID, delta: delta)
                    }
                }
            case .weight:
                NumericEntryPopup(title: "Weight", initialValue: weight ?? 0, unit: "lb", allowsDecimal: true) { newValue in
                    let delta = newValue - (weight ?? 0)
                    if delta != 0 {
                        Haptics.selection()
                        session.adjustWeight(forStepID: stepID, delta: delta)
                    }
                }
            }
        }
    }

    private static func formatWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

/// One floating "− value unit +" line. Minimal, ungrouped glyph buttons (large ~46pt tap targets,
/// light-weight glyph, subdued color) flank a big bold value — no glass, no pill background.
///
/// The value+unit block uses a fixed, CENTER-aligned frame (rather than a wider leading-aligned
/// one) so it never grows lopsided room to one side as digit count changes — that asymmetry is
/// what used to visually drag the whole "12 reps" cluster (and therefore the number itself) left
/// of screen-center once the row was centered by its parent, since the minus/plus glyph buttons
/// are equal-width and equally spaced either side of this block. Tapping that block (rather than
/// dragging or tapping the ± buttons) opens the numeric keypad popup via `onTapValue`.
private struct FloatingStepRow: View {
    let displayValue: Double
    let formattedText: String
    let unit: String
    var step: Double = 1
    var onAdjust: (Double) -> Void
    var onTapValue: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            GlyphButton(symbol: "minus", label: "Decrease \(unit)") { onAdjust(-step) }

            Button(action: onTapValue) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(formattedText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: displayValue))
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .frame(minWidth: 90, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.snappy, value: displayValue)
            .accessibilityLabel("\(unit) value")
            .accessibilityHint("Double tap to type an exact value")

            GlyphButton(symbol: "plus", label: "Increase \(unit)") { onAdjust(step) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(formattedText) \(unit)")
    }
}

/// A small sheet with a real numeric keyboard for typing an exact reps/weight value, opened by
/// tapping the value in `FloatingStepRow`. Reps use `.numberPad` (whole numbers only); weight uses
/// `.decimalPad` (`allowsDecimal`) so fractional plates (e.g. "47.5") can be entered. The field
/// auto-focuses the moment the sheet appears so the keyboard shows immediately, and both the
/// keyboard's return key and a "Done" button commit — `onCommit` reports the typed absolute value,
/// and the caller (`FloatingTargetRows`) converts it into a delta for the same `adjustReps`/
/// `adjustWeight` setters the − / + steppers use.
private struct NumericEntryPopup: View {
    let title: String
    let initialValue: Double
    let unit: String
    let allowsDecimal: Bool
    var onCommit: (Double) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialValue: Double, unit: String, allowsDecimal: Bool, onCommit: @escaping (Double) -> Void) {
        self.title = title
        self.initialValue = initialValue
        self.unit = unit
        self.allowsDecimal = allowsDecimal
        self.onCommit = onCommit
        _text = State(initialValue: allowsDecimal
            ? (initialValue.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(initialValue))" : String(format: "%.1f", initialValue))
            : "\(Int(initialValue))")
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text(title)
                .font(.title3.weight(.bold))

            HStack(spacing: 6) {
                TextField("Value", text: $text)
                    .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                    .focused($isFocused)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .onSubmit(commit)
                Text(unit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            Button("Done", action: commit)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        .task {
            // A tiny defer past `onAppear` so the sheet's presentation transition has started before
            // the keyboard slides up — avoids a race where focusing too early no-ops on some devices.
            try? await Task.sleep(nanoseconds: 80_000_000)
            isFocused = true
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    private func commit() {
        let sanitized = text.replacingOccurrences(of: ",", with: ".")
        if let value = Double(sanitized) {
            onCommit(max(0, value))
        }
        dismiss()
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
