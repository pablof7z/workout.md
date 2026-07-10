import SwiftUI
import Combine

/// The single most important screen in the app: one page = one set. Full-bleed background,
/// big calm typography, a quiet coach cue, and — inside a group — a round counter and mini-map.
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
    /// The bottom cluster is now the gesture bar (thumb + track): the 56pt round effort icon button
    /// sits above the 72pt track, above a small hint caption, all pinned above the safe area with
    /// 10pt of clearance from it, plus 26pt more so hero content never touches the glass track.
    /// (56 effort + 10 row gap + 72 track + 20 hint + 10 bottom padding + 26 clearance ≈ 194.)
    private var bottomReserve: CGFloat { bottomInset + 194 }

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
                HStack(spacing: 10) {
                    Text(info.exercise.name)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .strikethrough(info.skipped, color: .white.opacity(0.6))
                    if info.completed {
                        Text("DONE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .glassEffect(.regular.tint(.green), in: .capsule)
                    } else if info.skipped {
                        Text("SKIPPED")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .glassEffect(.regular.tint(.orange), in: .capsule)
                    }
                }

                Text("Set \(info.setNumber) of \(info.totalSets)")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))

                if case .timed(let seconds) = info.exercise.target {
                    TimedHeroView(totalSeconds: seconds)
                        .padding(.top, 6)
                } else {
                    FloatingTargetRows(stepID: step.id, skipped: info.skipped, locked: info.completed)
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
    let skipped: Bool
    /// True once the DONE gesture has logged this set as the "actual" — the +/- rows freeze so a
    /// stray tap after committing can't silently rewrite a logged number.
    var locked: Bool = false

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
        .opacity((skipped || locked) ? 0.45 : 1)
        .disabled(skipped || locked)
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
