import XCTest
@testable import WorkoutMD

final class TindeqTests: XCTestCase {
    func testDecodesOfficialWeightPacketShape() {
        var packet = Data([TindeqProtocol.Response.weightMeasurement.rawValue, 16])
        append(Float(28.5).bitPattern, to: &packet)
        append(1_000_000, to: &packet)
        append(Float(32.25).bitPattern, to: &packet)
        append(1_012_500, to: &packet)

        let samples = TindeqProtocol.decodeWeightSamples(packet)

        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].kilograms, 28.5, accuracy: 0.001)
        XCTAssertEqual(samples[0].timestampMicroseconds, 1_000_000)
        XCTAssertEqual(samples[1].kilograms, 32.25, accuracy: 0.001)
        XCTAssertEqual(samples[1].elapsedSeconds(since: samples[0]), 0.0125, accuracy: 0.000_001)
    }

    func testTrackerCompletesHoldAndCalculatesMetrics() {
        var tracker = TindeqSetTracker(seconds: 2, targetMinKg: 30, targetMaxKg: 34)
        let samples = (0...20).map { index in
            TindeqProtocol.WeightSample(
                kilograms: 32,
                timestampMicroseconds: UInt32(index * 100_000)
            )
        }

        tracker.ingest(samples)

        XCTAssertEqual(tracker.phase, .result(completed: true))
        XCTAssertEqual(tracker.peakKg, 32, accuracy: 0.001)
        XCTAssertEqual(tracker.averageKg, 32, accuracy: 0.001)
        XCTAssertEqual(tracker.elapsedSeconds, 2, accuracy: 0.001)
        XCTAssertEqual(tracker.timeInTargetSeconds, 2, accuracy: 0.001)
    }

    func testTrackerReportsBelowInAndAboveWithoutColor() {
        var tracker = TindeqSetTracker(seconds: 7, targetMinKg: 30, targetMaxKg: 34)

        tracker.ingest([.init(kilograms: 28, timestampMicroseconds: 0)])
        XCTAssertEqual(tracker.zone, .below(deltaKg: 2))

        tracker.ingest([.init(kilograms: 32, timestampMicroseconds: 100_000)])
        XCTAssertEqual(tracker.zone, .inTarget)

        tracker.ingest([.init(kilograms: 36, timestampMicroseconds: 200_000)])
        XCTAssertEqual(tracker.zone, .above(deltaKg: 2))
    }

    func testTrackerEndsAsReleasedEarlyAfterSustainedUnload() {
        var tracker = TindeqSetTracker(seconds: 7, targetMinKg: 30, targetMaxKg: 34)
        var samples: [TindeqProtocol.WeightSample] = []
        for index in 0...10 {
            samples.append(.init(kilograms: 32, timestampMicroseconds: UInt32(index * 100_000)))
        }
        for index in 11...15 {
            samples.append(.init(kilograms: 0, timestampMicroseconds: UInt32(index * 100_000)))
        }

        tracker.ingest(samples)

        XCTAssertEqual(tracker.phase, .result(completed: false))
        XCTAssertEqual(tracker.elapsedSeconds, 1.5, accuracy: 0.001)
    }

    func testTindeqTargetAndResultSurviveResumeAndHistory() throws {
        let exercise = Exercise(
            name: "Half crimp",
            cue: "Keep the shoulder engaged",
            target: .tindeq(seconds: 7, targetMinKg: 30, targetMaxKg: 34),
            moodKey: .plank
        )
        let info = SetPageInfo(
            exercise: exercise,
            setNumber: 1,
            totalSets: 1,
            groupLabel: nil,
            groupKind: nil,
            round: nil,
            totalRounds: nil,
            miniMap: nil
        )
        let step = WorkoutStep(
            blockIndex: 0,
            blockName: "Hangboard",
            moodKey: .plank,
            page: .set(info),
            exerciseName: exercise.name
        )
        let result = TindeqSetResult(
            peakKg: 35.2,
            averageKg: 32.1,
            holdSeconds: 7,
            timeInTargetSeconds: 6.3
        )
        let session = WorkoutSession(steps: [step])
        session.setTindeqResult(result, for: step.id)
        session.setState(.done, for: step.id)

        let encoded = try JSONEncoder().encode(SessionState.from(session))
        let decoded = try JSONDecoder().decode(SessionState.self, from: encoded)
        let restored = WorkoutSession.restore(from: decoded, modelContext: nil)

        guard case .set(let restoredInfo) = restored.steps.first?.page,
              case .tindeq(let seconds, let minimum, let maximum) = restoredInfo.exercise.target else {
            return XCTFail("expected restored Tindeq target")
        }
        XCTAssertEqual(seconds, 7)
        XCTAssertEqual(minimum, 30)
        XCTAssertEqual(maximum, 34)
        XCTAssertEqual(restored.tindeqResults[step.id], result)

        let history = restored.makeRecord(workoutName: "Grip", goal: nil)
        let recorded = try XCTUnwrap(history.exercises.first?.sets.first)
        XCTAssertEqual(recorded.prescribedSeconds, 7)
        XCTAssertEqual(recorded.prescribedTargetMinKg, 30)
        XCTAssertEqual(recorded.prescribedTargetMaxKg, 34)
        XCTAssertEqual(recorded.actualSeconds, 7)
        XCTAssertEqual(recorded.actualPeakKg, 35.2)
        XCTAssertEqual(recorded.actualAverageKg, 32.1)
        XCTAssertEqual(recorded.actualTimeInTargetSeconds, 6.3)
    }

    private func append(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
