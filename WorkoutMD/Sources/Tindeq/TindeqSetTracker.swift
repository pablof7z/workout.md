import Foundation

/// Pure measurement state machine used by the live view and unit tests. It starts hands-free when
/// meaningful load appears, finishes at the prescribed duration, and also detects an early release.
struct TindeqSetTracker: Equatable {
    enum Phase: Equatable {
        case ready
        case pulling
        case result(completed: Bool)
    }

    enum Zone: Equatable {
        case below(deltaKg: Double)
        case inTarget
        case above(deltaKg: Double)
    }

    let targetSeconds: Double
    let targetMinKg: Double
    let targetMaxKg: Double

    private(set) var phase: Phase = .ready
    private(set) var currentKg: Double = 0
    private(set) var elapsedSeconds: Double = 0
    private(set) var peakKg: Double = 0
    private(set) var averageKg: Double = 0
    private(set) var timeInTargetSeconds: Double = 0
    private(set) var trace: [Double] = []

    private var firstPullSample: TindeqProtocol.WeightSample?
    private var previousSample: TindeqProtocol.WeightSample?
    private var firstBelowThresholdSample: TindeqProtocol.WeightSample?
    private var forceIntegral: Double = 0
    private var measuredSeconds: Double = 0

    init(seconds: Int, targetMinKg: Double, targetMaxKg: Double) {
        self.targetSeconds = Double(max(seconds, 1))
        self.targetMinKg = min(targetMinKg, targetMaxKg)
        self.targetMaxKg = max(targetMinKg, targetMaxKg)
    }

    var zone: Zone {
        if currentKg < targetMinKg { return .below(deltaKg: targetMinKg - currentKg) }
        if currentKg > targetMaxKg { return .above(deltaKg: currentKg - targetMaxKg) }
        return .inTarget
    }

    var result: TindeqSetResult? {
        guard case .result = phase else { return nil }
        return TindeqSetResult(
            peakKg: peakKg,
            averageKg: averageKg,
            holdSeconds: elapsedSeconds,
            timeInTargetSeconds: timeInTargetSeconds
        )
    }

    mutating func ingest(_ samples: [TindeqProtocol.WeightSample]) {
        for sample in samples { ingest(sample) }
    }

    mutating func reset() {
        phase = .ready
        currentKg = 0
        elapsedSeconds = 0
        peakKg = 0
        averageKg = 0
        timeInTargetSeconds = 0
        trace = []
        firstPullSample = nil
        previousSample = nil
        firstBelowThresholdSample = nil
        forceIntegral = 0
        measuredSeconds = 0
    }

    private var activationThresholdKg: Double {
        max(2, targetMinKg * 0.25)
    }

    private mutating func ingest(_ sample: TindeqProtocol.WeightSample) {
        guard case .result = phase else {
            currentKg = max(0, sample.kilograms)
            appendTrace(currentKg)

            if phase == .ready, currentKg >= activationThresholdKg {
                phase = .pulling
                firstPullSample = sample
                previousSample = sample
                peakKg = currentKg
                return
            }

            guard phase == .pulling, let start = firstPullSample else { return }
            let dt = previousSample.map { min(max(sample.elapsedSeconds(since: $0), 0), 0.25) } ?? 0
            elapsedSeconds = min(sample.elapsedSeconds(since: start), targetSeconds)
            peakKg = max(peakKg, currentKg)
            if dt > 0 {
                forceIntegral += currentKg * dt
                measuredSeconds += dt
                averageKg = forceIntegral / measuredSeconds
                if currentKg >= targetMinKg, currentKg <= targetMaxKg {
                    timeInTargetSeconds += dt
                }
            }
            previousSample = sample

            if currentKg < activationThresholdKg {
                if firstBelowThresholdSample == nil { firstBelowThresholdSample = sample }
                if let below = firstBelowThresholdSample,
                   sample.elapsedSeconds(since: below) >= 0.35,
                   elapsedSeconds >= 0.5 {
                    phase = .result(completed: false)
                }
            } else {
                firstBelowThresholdSample = nil
            }

            if elapsedSeconds >= targetSeconds {
                phase = .result(completed: true)
            }
            return
        }
    }

    private mutating func appendTrace(_ value: Double) {
        trace.append(value)
        if trace.count > 96 { trace.removeFirst(trace.count - 96) }
    }
}
