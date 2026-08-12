import SwiftUI

/// Full-bleed, hands-free runner surface for a Tindeq set. It intentionally replaces the normal
/// done/skip thumb while load is applied: the sensor starts the hold, the planned duration ends it,
/// and Retry/Keep appear only after release.
struct TindeqSetView: View {
    @Environment(WorkoutSession.self) private var session
    @Environment(TindeqManager.self) private var tindeq

    let step: WorkoutStep
    let info: SetPageInfo
    let seconds: Int
    let targetMinKg: Double
    let targetMaxKg: Double
    let topReserve: CGFloat
    let bottomReserve: CGFloat

    @State private var tracker: TindeqSetTracker
    @State private var previousZone: ZoneKey?
    @ScaledMetric(relativeTo: .largeTitle) private var forceSize: CGFloat = 104

    private enum ZoneKey { case below, target, above }

    init(
        step: WorkoutStep,
        info: SetPageInfo,
        seconds: Int,
        targetMinKg: Double,
        targetMaxKg: Double,
        topReserve: CGFloat,
        bottomReserve: CGFloat
    ) {
        self.step = step
        self.info = info
        self.seconds = seconds
        self.targetMinKg = targetMinKg
        self.targetMaxKg = targetMaxKg
        self.topReserve = topReserve
        self.bottomReserve = bottomReserve
        _tracker = State(initialValue: TindeqSetTracker(
            seconds: seconds, targetMinKg: targetMinKg, targetMaxKg: targetMaxKg))
    }

    var body: some View {
        Group {
            if let result = displayedResult {
                resultContent(result)
            } else if tindeq.state == .sampling {
                liveContent
            } else {
                connectionContent
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, topReserve)
        .padding(.bottom, max(bottomReserve - 28, 44))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: activateIfNeeded)
        .onDisappear { tindeq.deactivate(for: step.id) }
        .onChange(of: session.currentStepID) { _, _ in activateIfNeeded() }
        .onChange(of: tindeq.measurementRevision) { _, _ in ingestLatestSamples() }
    }

    private var displayedResult: TindeqSetResult? {
        tracker.result ?? session.tindeqResults[step.id]
    }

    private var isCurrent: Bool { session.currentStepID == step.id }

    private func activateIfNeeded() {
        guard isCurrent, info.state == .pending, session.tindeqResults[step.id] == nil else { return }
        tindeq.activate(for: step.id)
    }

    private func ingestLatestSamples() {
        guard isCurrent, tindeq.state == .sampling, displayedResult == nil else { return }
        let previousPhase = tracker.phase
        tracker.ingest(tindeq.latestSamples)

        let newZone = zoneKey
        if tracker.phase == .pulling, newZone != previousZone {
            Haptics.selection()
        }
        previousZone = newZone

        if case .result(let completed) = tracker.phase, case .pulling = previousPhase {
            completed ? Haptics.success() : Haptics.impact(.light)
            tindeq.stopMeasurement()
        }
    }

    // MARK: - Connection / setup

    private var connectionContent: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: connectionSymbol)
                .font(.system(size: 54, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)

            Text(connectionTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            Text(connectionMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: 300)

            if canRetry {
                Button("Connect Tindeq") { tindeq.retry() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
            }

#if targetEnvironment(simulator)
            Button("Preview sensor") { tindeq.startDemo() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
#endif

            Button("Skip set") { skipSet() }
                .buttonStyle(.plain)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
                .frame(minHeight: 44)

            Spacer()
        }
    }

    private var connectionSymbol: String {
        switch tindeq.state {
        case .failed, .unavailable: return "exclamationmark.triangle"
        default: return "sensor.tag.radiowaves.forward"
        }
    }

    private var connectionTitle: String {
        switch tindeq.state {
        case .scanning: return "Searching for Tindeq"
        case .connecting, .preparing: return "Connecting"
        case .failed: return "Connection lost"
        case .unavailable: return "Bluetooth unavailable"
        default: return "Connect Tindeq"
        }
    }

    private var connectionMessage: String {
        switch tindeq.state {
        case .unavailable(let message), .failed(let message): return message
        case .scanning: return "Wake the Progressor. It connects here—not in Bluetooth Settings."
        case .connecting, .preparing: return "Preparing the sensor and zeroing the load."
        default: return "Wake the Progressor to measure this hang automatically."
        }
    }

    private var canRetry: Bool {
        switch tindeq.state {
        case .idle, .failed, .unavailable: return true
        default: return false
        }
    }

    // MARK: - Live pull

    private var liveContent: some View {
        VStack(spacing: 12) {
            Text("SET \(info.setNumber) OF \(info.totalSets)")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Image(systemName: zoneSymbol)
                Text(zoneTitle)
            }
            .font(.title3.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(zoneColor)

            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(kilograms(tracker.currentKg))
                    .font(.system(size: forceSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text("kg")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)

            Text("\(kilograms(targetMinKg))–\(kilograms(targetMaxKg)) kg")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))

            TindeqTargetCorridor(
                currentKg: tracker.currentKg,
                targetMinKg: targetMinKg,
                targetMaxKg: targetMaxKg,
                accent: zoneColor
            )
            .frame(height: 54)
            .padding(.top, 4)

            TindeqForceTrace(
                values: tracker.trace,
                targetMinKg: targetMinKg,
                targetMaxKg: targetMaxKg,
                accent: zoneColor
            )
            .frame(height: 105)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(oneDecimal(tracker.elapsedSeconds))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text("/ \(seconds) sec")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)

            Text(instruction)
                .font(.headline.weight(.bold))
                .tracking(2)
                .foregroundStyle(zoneColor)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tindeq hold, \(zoneTitle), \(kilograms(tracker.currentKg)) kilograms, \(oneDecimal(tracker.elapsedSeconds)) of \(seconds) seconds")
    }

    private var zoneKey: ZoneKey {
        switch tracker.zone {
        case .below: return .below
        case .inTarget: return .target
        case .above: return .above
        }
    }

    private var zoneTitle: String {
        guard tracker.phase != .ready else { return "LOAD TO START" }
        switch tracker.zone {
        case .below(let delta): return "PULL \(kilograms(delta)) KG MORE"
        case .inTarget: return "IN TARGET"
        case .above(let delta): return "EASE \(kilograms(delta)) KG"
        }
    }

    private var zoneSymbol: String {
        guard tracker.phase != .ready else { return "arrow.up" }
        switch tracker.zone {
        case .below: return "arrow.up"
        case .inTarget: return "checkmark.circle"
        case .above: return "arrow.down"
        }
    }

    private var zoneColor: Color {
        guard tracker.phase != .ready else { return .white.opacity(0.8) }
        switch tracker.zone {
        case .inTarget: return .green
        case .below, .above: return .orange
        }
    }

    private var instruction: String {
        guard tracker.phase != .ready else { return "APPLY LOAD" }
        switch tracker.zone {
        case .inTarget: return "HOLD STEADY"
        case .below: return "KEEP PULLING"
        case .above: return "EASE SLIGHTLY"
        }
    }

    // MARK: - Result

    private func resultContent(_ result: TindeqSetResult) -> some View {
        VStack(spacing: 18) {
            Text(resultTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            TindeqForceTrace(
                values: tracker.trace,
                targetMinKg: targetMinKg,
                targetMaxKg: targetMaxKg,
                accent: .green
            )
            .frame(height: 145)

            HStack(spacing: 28) {
                resultMetric("PEAK", value: "\(kilograms(result.peakKg)) kg")
                resultMetric("AVERAGE", value: "\(kilograms(result.averageKg)) kg")
            }

            HStack(spacing: 28) {
                resultMetric("HOLD", value: "\(oneDecimal(result.holdSeconds)) sec")
                resultMetric("IN TARGET", value: "\(oneDecimal(result.timeInTargetSeconds)) sec")
            }

            if tindeq.lowBattery {
                Label("Tindeq battery is low", systemImage: "battery.25")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Retry") { retrySet() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                Button(info.state == .done ? "Next" : "Keep") { keepResult(result) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var resultTitle: String {
        if info.state == .done { return "Recorded" }
        if case .result(let completed) = tracker.phase {
            return completed ? "Hold complete" : "Released early"
        }
        return "Hold complete"
    }

    private func resultMetric(_ label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private func retrySet() {
        session.clearTindeqResult(for: step.id)
        session.setState(.pending, for: step.id)
        tracker.reset()
        previousZone = nil
        tindeq.activate(for: step.id)
    }

    private func keepResult(_ result: TindeqSetResult) {
        if info.state != .done {
            session.setTindeqResult(result, for: step.id)
            session.setState(.done, for: step.id)
            Haptics.success()
        }
        tindeq.deactivate(for: step.id)
        session.advanceToNextStep(after: step.id)
    }

    private func skipSet() {
        tindeq.deactivate(for: step.id)
        session.setState(.skipped, for: step.id)
        Haptics.impact(.light)
        session.advanceToNextStep(after: step.id)
    }

    private func kilograms(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct TindeqTargetCorridor: View {
    let currentKg: Double
    let targetMinKg: Double
    let targetMaxKg: Double
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let lower = max(0, targetMinKg - max(5, (targetMaxKg - targetMinKg)))
            let upper = max(targetMaxKg + max(5, targetMaxKg - targetMinKg), lower + 1)
            let xMin = x(targetMinKg, lower: lower, upper: upper, width: proxy.size.width)
            let xMax = x(targetMaxKg, lower: lower, upper: upper, width: proxy.size.width)
            let markerX = x(currentKg, lower: lower, upper: upper, width: proxy.size.width)

            ZStack(alignment: .leading) {
                Capsule()
                    .stroke(.white.opacity(0.35), lineWidth: 2)
                    .frame(height: 22)
                    .offset(y: 16)
                RoundedRectangle(cornerRadius: 6)
                    .fill(accent.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent, lineWidth: 2))
                    .frame(width: max(xMax - xMin, 2), height: 22)
                    .offset(x: xMin, y: 16)
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(accent, lineWidth: 3))
                    .frame(width: 18, height: 18)
                    .offset(x: markerX - 9, y: 18)
            }
        }
        .accessibilityHidden(true)
    }

    private func x(_ value: Double, lower: Double, upper: Double, width: CGFloat) -> CGFloat {
        CGFloat(min(max((value - lower) / (upper - lower), 0), 1)) * width
    }
}

private struct TindeqForceTrace: View {
    let values: [Double]
    let targetMinKg: Double
    let targetMaxKg: Double
    let accent: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let ceiling = max(values.max() ?? 0, targetMaxKg * 1.18, 1)

            let targetTop = size.height * (1 - CGFloat(targetMaxKg / ceiling))
            let targetBottom = size.height * (1 - CGFloat(targetMinKg / ceiling))
            let targetRect = CGRect(
                x: 0, y: targetTop, width: size.width,
                height: max(targetBottom - targetTop, 2))
            context.fill(Path(roundedRect: targetRect, cornerRadius: 4), with: .color(accent.opacity(0.09)))

            var path = Path()
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) / CGFloat(values.count - 1) * size.width
                let y = size.height * (1 - CGFloat(min(max(value / ceiling, 0), 1)))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(accent), lineWidth: 3)
        }
        .accessibilityHidden(true)
    }
}
