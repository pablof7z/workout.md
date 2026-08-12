import XCTest
import SwiftData
@testable import WorkoutMD

/// Unit tests for the durable active-workout snapshot (`docs/architecture/domain-primitives.md`
/// §8): `SessionState`'s plan-independent round-trip, `ActiveSessionStore`'s persist/resume/
/// finish/discard lifecycle, and the core "structural live edit preserves history" invariant that
/// `WorkoutSession.makeRecord`'s id-keyed join (`PersistenceModels.swift`) now guarantees instead
/// of the old `zip(prescribedSteps, steps)`. Uses an in-memory `ModelContainer` (mirrors
/// `PlanRepositoryTests`/`AppCoachHostTests`) so every test starts from a clean store.
final class ActiveSessionTests: XCTestCase {

    // MARK: - Fixture

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutRecord.self,
            ExerciseRecord.self,
            SetRecord.self,
            CoachNoteRecord.self,
            HeartRateSampleRecord.self,
            PlanRecord.self,
            PlanBlockRecord.self,
            PlanExerciseRecord.self,
            PlanSetRecord.self,
            PlanSessionRecord.self,
            PlanRevisionRecord.self,
            MemoryRecord.self,
            ActiveSessionRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// A small, real plan/session built the ordinary way (`DefaultPlanSeed` + `toWorkoutSteps`) —
    /// mirrors how `RootView.startSession` builds a `WorkoutSession` in the app. Bench Press (a
    /// straight-sets, 3-set block, 10 reps @ 135 lb) is always the first 3 steps.
    private func makeSession(context: ModelContext) -> WorkoutSession {
        let plan = DefaultPlanSeed.makePlanRecord()
        context.insert(plan)
        try? context.save()
        return WorkoutSession(steps: plan.toWorkoutSteps(), activePlan: plan, modelContext: context)
    }

    // MARK: - 1. SessionState round-trip

    func testSessionStateRoundTripPreservesStepsIDsStatesTargetsCursorAndRPE() throws {
        let context = try makeContext()
        let session = makeSession(context: context)
        guard session.steps.count >= 3 else { return XCTFail("expected at least 3 steps") }

        let firstID = session.steps[0].id
        let secondID = session.steps[1].id

        session.setState(.done, for: firstID)
        session.adjustReps(forStepID: firstID, delta: 2)
        session.setEffort(8.5, for: firstID)
        session.recordHeartRate(
            HeartRateSample(timestamp: Date(timeIntervalSince1970: 1_700_000_000), beatsPerMinute: 142),
            sensorName: "Polar H10 12345678"
        )
        session.skip(forStepID: secondID)
        session.currentStepID = secondID

        let data = try JSONEncoder().encode(SessionState.from(session))
        let decoded = try JSONDecoder().decode(SessionState.self, from: data)
        let restored = WorkoutSession.restore(from: decoded, modelContext: context)

        XCTAssertEqual(restored.steps.map(\.id), session.steps.map(\.id), "step ids preserved, in order")
        XCTAssertEqual(restored.currentStepID, secondID)
        XCTAssertEqual(restored.rpe[firstID], 8.5)
        XCTAssertEqual(restored.heartRateSamples, session.heartRateSamples)
        XCTAssertEqual(restored.heartRateSensorName, "Polar H10 12345678")
        XCTAssertEqual(restored.activePlan?.id, session.activePlan?.id)

        guard case .set(let firstInfo) = restored.steps[0].page, case .set(let liveFirstInfo) = session.steps[0].page else {
            return XCTFail("expected set pages")
        }
        XCTAssertEqual(firstInfo.state, .done)
        XCTAssertEqual(firstInfo.exercise.target.displayString, liveFirstInfo.exercise.target.displayString, "adjusted reps preserved")

        guard case .set(let secondInfo) = restored.steps[1].page else { return XCTFail("expected a set page") }
        XCTAssertEqual(secondInfo.state, .skipped)
    }

    // MARK: - 2. Durable persist / resume (simulates relaunch)

    func testActiveSessionStoreSavesAndANewStoreOnSameContextResumesEquivalentState() throws {
        let context = try makeContext()
        let session = makeSession(context: context)
        let firstID = session.steps[0].id
        session.setState(.done, for: firstID)
        session.setEffort(9, for: firstID)

        ActiveSessionStore(context: context).save(session)

        // A brand-new `ActiveSessionStore` value over the SAME context — simulates a fresh launch
        // reading the same persisted SwiftData store, not merely reusing the same Swift instance.
        let freshStore = ActiveSessionStore(context: context)
        let record = freshStore.currentInProgress()
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.status, "inProgress")

        let resumed = try XCTUnwrap(freshStore.loadSession(modelContext: context))
        XCTAssertEqual(resumed.steps.map(\.id), session.steps.map(\.id))
        XCTAssertEqual(resumed.rpe[firstID], 9)
        XCTAssertEqual(resumed.activePlan?.id, session.activePlan?.id)
        guard case .set(let info) = resumed.steps[0].page else { return XCTFail("expected a set page") }
        XCTAssertEqual(info.state, .done)
    }

    // MARK: - 3. markFinished / discard clear currentInProgress

    func testMarkFinishedClearsCurrentInProgress() throws {
        let context = try makeContext()
        let store = ActiveSessionStore(context: context)
        store.save(makeSession(context: context))
        XCTAssertNotNil(store.currentInProgress())

        store.markFinished()

        XCTAssertNil(store.currentInProgress())
    }

    func testDiscardClearsCurrentInProgress() throws {
        let context = try makeContext()
        let store = ActiveSessionStore(context: context)
        store.save(makeSession(context: context))
        XCTAssertNotNil(store.currentInProgress())

        store.discard()

        XCTAssertNil(store.currentInProgress())
    }

    // MARK: - 4. Structural live edit preserves history (the core invariant)

    /// Proves the id-keyed join in `makeRecord` can't be desynced by a structural live edit the way
    /// the old `zip(prescribedSteps, steps)` positional pairing could: mark a set done with an
    /// actual that diverges from prescribed, insert a brand-new set mid-session (shifting every
    /// later index by one), and skip a different, untouched set — then assert every `SetRecord`
    /// lands on the RIGHT set BY IDENTITY (`sourceStepID`), not by whatever position it ends up at.
    func testStructuralLiveEditPreservesPrescribedVsActualHistoryByIdentity() throws {
        let context = try makeContext()
        let session = makeSession(context: context)

        guard session.steps.count >= 3, case .set(let firstInfo) = session.steps[0].page else {
            return XCTFail("expected at least 3 set steps")
        }
        XCTAssertEqual(firstInfo.exercise.name, "Bench Press")

        let doneStepID = session.steps[0].id
        let skippedStepID = session.steps[2].id

        // 1. Log set 1 done with an ACTUAL that diverges from prescribed (135x10 -> 145x8).
        session.setState(.done, for: doneStepID)
        _ = session.setTarget(reps: 8, weight: 145, forStepID: doneStepID)

        // 2. Structural edit: add a brand-new set right after set 1 — exactly the kind of edit that
        // would shift array positions and desync a `zip`-based join.
        _ = session.addSet(afterStepID: doneStepID, reps: 10, weight: 135)
        let doneIndex = try XCTUnwrap(session.steps.firstIndex { $0.id == doneStepID })
        let addedStepID = session.steps[doneIndex + 1].id
        XCTAssertNotEqual(addedStepID, doneStepID)

        // 3. Skip a different, untouched prescribed set (now shifted one position later in `steps`).
        _ = session.skip(forStepID: skippedStepID)

        let record = session.makeRecord(workoutName: "Test", goal: nil)
        let benchSets = record.exercises.first { $0.name == "Bench Press" }?.sets.sorted { $0.order < $1.order } ?? []
        XCTAssertEqual(benchSets.count, 4, "the original 3 prescribed sets plus the one added live")

        let doneRecord = try XCTUnwrap(benchSets.first { $0.sourceStepID == doneStepID })
        XCTAssertEqual(doneRecord.prescribedReps, 10)
        XCTAssertEqual(doneRecord.prescribedWeight, 135)
        XCTAssertEqual(doneRecord.actualReps, 8)
        XCTAssertEqual(doneRecord.actualWeight, 145)
        XCTAssertFalse(doneRecord.skipped)

        let addedRecord = try XCTUnwrap(benchSets.first { $0.sourceStepID == addedStepID })
        XCTAssertNil(addedRecord.prescribedReps, "a set added live carries no prescribed corruption — honestly nil, never borrowed from a neighbor")
        XCTAssertNil(addedRecord.prescribedWeight)
        XCTAssertEqual(addedRecord.actualReps, 10)
        XCTAssertEqual(addedRecord.actualWeight, 135)

        let skippedRecord = try XCTUnwrap(benchSets.first { $0.sourceStepID == skippedStepID })
        XCTAssertTrue(skippedRecord.skipped)
        XCTAssertEqual(skippedRecord.prescribedReps, 10, "the untouched prescribed set's own prescription, not shifted onto a neighbor")
        XCTAssertNil(skippedRecord.actualReps, "skipped sets record no actual")
    }
}
