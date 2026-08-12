import XCTest
@testable import WorkoutMD

/// Unit tests for the canonical plan value layer (`PlanSnapshot`/`PlanOp`/`PlanMutation`/
/// `PlanEngine` — see `WorkoutMD/Sources/Plans/Canonical/`). These types are pure Foundation value
/// types with no SwiftData/SwiftUI coupling, so no fixtures beyond plain values are needed.
///
/// Compiled via `@testable import WorkoutMD` (see `project.yml`): `WorkoutMDTests` hosts against the
/// full `WorkoutMD` app target rather than compiling these sources a second time directly into the
/// test module, because `PlanRepositoryTests` (added alongside this file) needs `PlanRecord`/
/// `PlanRepository`/`PlanMigrator`, which transitively pull in the whole app (SwiftData models,
/// `Models.swift`, the Rust coach bridge) — compiling both a direct copy AND an imported copy of
/// `PlanSnapshot`/`PlanEngine` in the same module would make those type names ambiguous.
final class PlanEngineTests: XCTestCase {

    // MARK: - Creating a plan by mutation

    func testCreatingAPlanByApplyingMutationsToEmpty() throws {
        let planID = UUID()
        let sessionID = UUID()
        let blockID = UUID()
        let benchID = UUID()
        let set1ID = UUID()
        let set2ID = UUID()

        let empty = PlanEngine.empty(id: planID, name: "Upper/Lower")
        XCTAssertEqual(empty.id, planID)
        XCTAssertEqual(empty.name, "Upper/Lower")
        XCTAssertEqual(empty.sessions, [])
        XCTAssertNil(empty.cursorSessionID)

        let mutation = PlanMutation(
            operations: [
                .addSession(id: sessionID, name: "Upper A", index: nil),
                .addBlock(
                    sessionID: sessionID,
                    block: BlockSnapshot(
                        id: blockID, kind: .straight, label: "Bench Press", rounds: 1,
                        restSeconds: nil, exercises: []),
                    index: nil),
                .addExercise(
                    blockID: blockID,
                    exercise: ExerciseSnapshot(
                        id: benchID, name: "Bench Press", cue: "Elbows tucked", sets: []),
                    index: nil),
                .addSet(
                    exerciseID: benchID,
                    set: SetSnapshot(id: set1ID, reps: 8, weight: 135, seconds: nil), index: nil),
                .addSet(
                    exerciseID: benchID,
                    set: SetSnapshot(id: set2ID, reps: 8, weight: 135, seconds: nil), index: nil),
            ],
            summary: nil
        )

        let plan = try PlanEngine.apply(mutation, to: empty)

        XCTAssertEqual(plan.sessions.count, 1)
        let session = try XCTUnwrap(plan.findSession(sessionID))
        XCTAssertEqual(session.name, "Upper A")
        XCTAssertEqual(session.blocks.count, 1)
        XCTAssertEqual(session.blocks[0].id, blockID)
        XCTAssertEqual(session.blocks[0].label, "Bench Press")
        XCTAssertEqual(session.blocks[0].exercises.count, 1)
        let exercise = session.blocks[0].exercises[0]
        XCTAssertEqual(exercise.id, benchID)
        XCTAssertEqual(exercise.name, "Bench Press")
        XCTAssertEqual(exercise.sets.map(\.id), [set1ID, set2ID])
        XCTAssertEqual(exercise.sets.map(\.reps), [8, 8])
    }

    // MARK: - Atomicity

    func testAtomicBatchAddingABlockThenExercisesIntoItInOneMutationSucceeds() throws {
        let sessionID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let setID = UUID()

        var plan = PlanEngine.empty(name: "Plan")
        plan = try PlanEngine.apply(
            PlanMutation(operations: [.addSession(id: sessionID, name: "Day 1", index: nil)], summary: nil),
            to: plan)

        // A single mutation that adds a block AND adds an exercise (with a set) into that
        // caller-supplied block id, all in one atomic batch — the new-block id doesn't need to exist
        // in the snapshot yet when the mutation is constructed, only by the time its own op runs.
        let mutation = PlanMutation(
            operations: [
                .addBlock(
                    sessionID: sessionID,
                    block: BlockSnapshot(
                        id: blockID, kind: .straight, label: "Squat", rounds: 1, restSeconds: nil,
                        exercises: []),
                    index: nil),
                .addExercise(
                    blockID: blockID,
                    exercise: ExerciseSnapshot(id: exerciseID, name: "Squat", cue: "", sets: []),
                    index: nil),
                .addSet(
                    exerciseID: exerciseID,
                    set: SetSnapshot(id: setID, reps: 5, weight: 225, seconds: nil), index: nil),
            ],
            summary: nil
        )

        let result = try PlanEngine.apply(mutation, to: plan)
        let (block, _) = try XCTUnwrap(result.findBlock(blockID))
        XCTAssertEqual(block.exercises.first?.id, exerciseID)
        XCTAssertEqual(block.exercises.first?.sets.first?.id, setID)
    }

    func testBatchWithAnUnknownIDOnTheThirdOpThrowsAndLeavesInputUnchanged() {
        let sessionID = UUID()
        let blockID = UUID()

        var plan = PlanEngine.empty(name: "Plan")
        plan = try! PlanEngine.apply(
            PlanMutation(operations: [.addSession(id: sessionID, name: "Day 1", index: nil)], summary: nil),
            to: plan)
        plan = try! PlanEngine.apply(
            PlanMutation(
                operations: [
                    .addBlock(
                        sessionID: sessionID,
                        block: BlockSnapshot(
                            id: blockID, kind: .straight, label: "Squat", rounds: 1, restSeconds: nil,
                            exercises: []),
                        index: nil)
                ], summary: nil),
            to: plan)

        let inputSnapshot = plan
        let unknownExerciseID = UUID()

        let mutation = PlanMutation(
            operations: [
                // Op 1: succeeds.
                .updateSession(id: sessionID, name: .set("Day 1 (renamed)")),
                // Op 2: succeeds.
                .updateBlock(
                    id: blockID, kind: .keep, label: .set("Squat (renamed)"), rounds: .keep,
                    restSeconds: .keep),
                // Op 3: references an id that doesn't exist — must throw.
                .updateExercise(id: unknownExerciseID, name: .set("Ghost"), cue: .keep),
            ],
            summary: nil
        )

        XCTAssertThrowsError(try PlanEngine.apply(mutation, to: plan)) { error in
            XCTAssertEqual(error as? PlanEngineError, .unknownID(unknownExerciseID))
        }

        // The ops before the failing one must NOT have leaked into the caller's snapshot: `plan` is
        // untouched (proves atomicity — Swift value semantics mean `apply` only ever mutated a local
        // working copy, and returning without hitting `return working` discards it).
        XCTAssertEqual(plan, inputSnapshot)
        XCTAssertEqual(plan.sessions.first?.name, "Day 1")
        XCTAssertEqual(plan.sessions.first?.blocks.first?.label, "Squat")
    }

    // MARK: - Stable identity

    func testUpdatingASetByIDChangesOnlyThatSetSiblingsUntouched() throws {
        let (plan, ids) = try makeTwoSetExercisePlan()

        let mutation = PlanMutation(
            operations: [.updateSet(
                id: ids.set1, reps: .set(10), weight: .keep, seconds: .keep,
                targetMinKg: .keep, targetMaxKg: .keep)],
            summary: nil)
        let result = try PlanEngine.apply(mutation, to: plan)

        let exercise = try XCTUnwrap(result.findExercise(ids.exercise)).exercise
        XCTAssertEqual(exercise.sets[0].id, ids.set1)
        XCTAssertEqual(exercise.sets[0].reps, 10)
        // Sibling set is byte-for-byte unchanged, including its id.
        XCTAssertEqual(exercise.sets[1], plan.findSet(ids.set2)?.set)
        XCTAssertEqual(exercise.sets.map(\.id), [ids.set1, ids.set2])
    }

    func testReorderingBlocksExercisesAndSetsPreservesIdsAndOnlyChangesOrder() throws {
        let (plan, ids) = try makeTwoSetExercisePlan()

        // Reorder the two sets within the exercise (move the second set to index 0).
        let mutation = PlanMutation(
            operations: [.moveSet(id: ids.set2, toExerciseID: nil, toIndex: 0)], summary: nil)
        let result = try PlanEngine.apply(mutation, to: plan)

        let exercise = try XCTUnwrap(result.findExercise(ids.exercise)).exercise
        XCTAssertEqual(exercise.sets.map(\.id), [ids.set2, ids.set1])
        // Same set of ids, same reps values attached to the same ids — nothing was recreated.
        XCTAssertEqual(Set(exercise.sets.map(\.id)), Set([ids.set1, ids.set2]))
    }

    func testMoveBlockAcrossSessionsPreservesBlockAndDescendantIds() throws {
        let sessionAID = UUID()
        let sessionBID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let setID = UUID()

        var plan = PlanEngine.empty(name: "Plan")
        plan = try PlanEngine.apply(
            PlanMutation(
                operations: [
                    .addSession(id: sessionAID, name: "A", index: nil),
                    .addSession(id: sessionBID, name: "B", index: nil),
                    .addBlock(
                        sessionID: sessionAID,
                        block: BlockSnapshot(
                            id: blockID, kind: .straight, label: "Row", rounds: 1, restSeconds: nil,
                            exercises: [
                                ExerciseSnapshot(
                                    id: exerciseID, name: "Row", cue: "", sets: [
                                        SetSnapshot(id: setID, reps: 10, weight: nil, seconds: nil)
                                    ])
                            ]),
                        index: nil),
                ], summary: nil),
            to: plan)

        let moved = try PlanEngine.apply(
            PlanMutation(
                operations: [.moveBlock(id: blockID, toSessionID: sessionBID, toIndex: 0)],
                summary: nil),
            to: plan)

        XCTAssertEqual(moved.findSession(sessionAID)?.blocks.count, 0)
        let (block, sessionID) = try XCTUnwrap(moved.findBlock(blockID))
        XCTAssertEqual(sessionID, sessionBID)
        XCTAssertEqual(block.exercises.first?.id, exerciseID)
        XCTAssertEqual(block.exercises.first?.sets.first?.id, setID)
    }

    /// Builds a one-session / one-block / one-exercise / two-set plan and returns the stable ids
    /// used throughout, so identity tests don't repeat this scaffolding.
    private func makeTwoSetExercisePlan() throws -> (
        plan: PlanSnapshot, ids: (session: UUID, block: UUID, exercise: UUID, set1: UUID, set2: UUID)
    ) {
        let sessionID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let set1ID = UUID()
        let set2ID = UUID()

        let plan = try PlanEngine.apply(
            PlanMutation(
                operations: [
                    .addSession(id: sessionID, name: "Day 1", index: nil),
                    .addBlock(
                        sessionID: sessionID,
                        block: BlockSnapshot(
                            id: blockID, kind: .straight, label: "Bench", rounds: 1, restSeconds: nil,
                            exercises: []),
                        index: nil),
                    .addExercise(
                        blockID: blockID,
                        exercise: ExerciseSnapshot(id: exerciseID, name: "Bench", cue: "", sets: []),
                        index: nil),
                    .addSet(
                        exerciseID: exerciseID,
                        set: SetSnapshot(id: set1ID, reps: 8, weight: 135, seconds: nil), index: nil),
                    .addSet(
                        exerciseID: exerciseID,
                        set: SetSnapshot(id: set2ID, reps: 8, weight: 135, seconds: nil), index: nil),
                ], summary: nil),
            to: PlanEngine.empty(name: "Plan"))

        return (plan, (sessionID, blockID, exerciseID, set1ID, set2ID))
    }

    // MARK: - FieldEdit semantics, driven through JSON decode

    func testUpdateSetFieldEditSemanticsThroughJSONDecodeAbsentVsNullVsValue() throws {
        let setID = UUID()
        let decoder = JSONDecoder()

        let keepOp = try decoder.decode(
            PlanOp.self,
            from: Data(#"{"op":"updateSet","id":"\#(setID.uuidString.lowercased())"}"#.utf8))
        guard case let .updateSet(id, reps, weight, seconds, targetMinKg, targetMaxKg) = keepOp else {
            return XCTFail("expected .updateSet")
        }
        XCTAssertEqual(id, setID)
        XCTAssertEqual(reps, .keep)
        XCTAssertEqual(weight, .keep)
        XCTAssertEqual(seconds, .keep)
        XCTAssertEqual(targetMinKg, .keep)
        XCTAssertEqual(targetMaxKg, .keep)

        let clearOp = try decoder.decode(
            PlanOp.self,
            from: Data(
                #"{"op":"updateSet","id":"\#(setID.uuidString.lowercased())","weight":null}"#.utf8))
        guard case let .updateSet(_, _, weight2, _, _, _) = clearOp else {
            return XCTFail("expected .updateSet")
        }
        XCTAssertEqual(weight2, .clear)

        let setOp = try decoder.decode(
            PlanOp.self,
            from: Data(
                #"{"op":"updateSet","id":"\#(setID.uuidString.lowercased())","weight":142.5}"#.utf8))
        guard case let .updateSet(_, _, weight3, _, _, _) = setOp else {
            return XCTFail("expected .updateSet")
        }
        XCTAssertEqual(weight3, .set(142.5))
    }

    func testFieldEditAppliedEndToEndKeepClearAndSetOnAWeight() throws {
        let (plan, ids) = try makeTwoSetExercisePlan()
        XCTAssertEqual(plan.findSet(ids.set1)?.set.weight, 135)

        // .keep leaves weight untouched.
        let kept = try PlanEngine.apply(
            PlanMutation(
                operations: [.updateSet(
                    id: ids.set1, reps: .keep, weight: .keep, seconds: .keep,
                    targetMinKg: .keep, targetMaxKg: .keep)],
                summary: nil),
            to: plan)
        XCTAssertEqual(kept.findSet(ids.set1)?.set.weight, 135)

        // .clear nils it out.
        let cleared = try PlanEngine.apply(
            PlanMutation(
                operations: [.updateSet(
                    id: ids.set1, reps: .keep, weight: .clear, seconds: .keep,
                    targetMinKg: .keep, targetMaxKg: .keep)],
                summary: nil),
            to: plan)
        XCTAssertNil(cleared.findSet(ids.set1)?.set.weight)

        // .set changes it.
        let updated = try PlanEngine.apply(
            PlanMutation(
                operations: [.updateSet(
                    id: ids.set1, reps: .keep, weight: .set(140), seconds: .keep,
                    targetMinKg: .keep, targetMaxKg: .keep)],
                summary: nil),
            to: plan)
        XCTAssertEqual(updated.findSet(ids.set1)?.set.weight, 140)
    }

    // MARK: - JSON round-trip

    func testJSONRoundTripEveryOpKind() throws {
        let ops: [PlanOp] = [
            .setPlanMeta(name: .set("New Name"), goal: .clear, notes: .keep),
            .addSession(id: UUID(), name: "Day 1", index: nil),
            .updateSession(id: UUID(), name: .set("Renamed")),
            .removeSession(id: UUID()),
            .moveSession(id: UUID(), toIndex: 2),
            .setCursor(sessionID: UUID()),
            .setCursor(sessionID: nil),
            .addBlock(
                sessionID: UUID(),
                block: BlockSnapshot(
                    id: UUID(), kind: .superset, label: "Push", rounds: 3, restSeconds: 60,
                    exercises: []),
                index: 1),
            .updateBlock(
                id: UUID(), kind: .set(.circuit), label: .keep, rounds: .set(4),
                restSeconds: .clear),
            .removeBlock(id: UUID()),
            .moveBlock(id: UUID(), toSessionID: UUID(), toIndex: 0),
            .moveBlock(id: UUID(), toSessionID: nil, toIndex: 1),
            .addExercise(
                blockID: UUID(),
                exercise: ExerciseSnapshot(id: UUID(), name: "Row", cue: "Squeeze", sets: []),
                index: nil),
            .updateExercise(id: UUID(), name: .keep, cue: .set("New cue")),
            .replaceExercise(
                id: UUID(), name: "Deadlift", cue: .clear,
                sets: [SetSnapshot(id: UUID(), reps: 5, weight: 225, seconds: nil)]),
            .replaceExercise(id: UUID(), name: "Deadlift", cue: .keep, sets: nil),
            .removeExercise(id: UUID()),
            .moveExercise(id: UUID(), toBlockID: UUID(), toIndex: 2),
            .addSet(
                exerciseID: UUID(), set: SetSnapshot(id: UUID(), reps: 8, weight: 95, seconds: nil),
                index: 0),
            .updateSet(
                id: UUID(), reps: .set(6), weight: .clear, seconds: .keep,
                targetMinKg: .keep, targetMaxKg: .keep),
            .removeSet(id: UUID()),
            .moveSet(id: UUID(), toExerciseID: UUID(), toIndex: 0),
        ]
        let mutation = PlanMutation(operations: ops, summary: "Everything at once")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(mutation)
        let decoded = try decoder.decode(PlanMutation.self, from: data)

        XCTAssertEqual(decoded, mutation)
    }

    func testWireShapeHasOpDiscriminatorAndOmitsKeepEncodesClearAsNull() throws {
        let setID = UUID()
        let op = PlanOp.updateSet(
            id: setID, reps: .keep, weight: .clear, seconds: .set(30),
            targetMinKg: .keep, targetMaxKg: .keep)

        let data = try JSONEncoder().encode(op)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["op"] as? String, "updateSet")
        XCTAssertEqual(object["id"] as? String, setID.uuidString.lowercased())
        // .keep ⇒ key entirely absent.
        XCTAssertNil(object["reps"])
        XCTAssertFalse(object.keys.contains("reps"))
        // .clear ⇒ key present with JSON null.
        XCTAssertTrue(object.keys.contains("weight"))
        XCTAssertTrue(object["weight"] is NSNull)
        // .set(v) ⇒ key present with the value.
        XCTAssertEqual(object["seconds"] as? Int, 30)
    }

    func testWireShapeOmitsIndexWhenNilAndIncludesItWhenPresent() throws {
        let exerciseID = UUID()
        let setA = SetSnapshot(id: UUID(), reps: 5, weight: nil, seconds: nil)

        let appendOp = PlanOp.addSet(exerciseID: exerciseID, set: setA, index: nil)
        let appendData = try JSONEncoder().encode(appendOp)
        let appendObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: appendData) as? [String: Any])
        XCTAssertEqual(appendObject["op"] as? String, "addSet")
        XCTAssertFalse(appendObject.keys.contains("index"))

        let insertOp = PlanOp.addSet(exerciseID: exerciseID, set: setA, index: 3)
        let insertData = try JSONEncoder().encode(insertOp)
        let insertObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: insertData) as? [String: Any])
        XCTAssertEqual(insertObject["index"] as? Int, 3)
    }

    // MARK: - Cursor / next-session resolution

    func testMultiSessionPlanResolvesNextSessionFromCursorAndAdvancing() throws {
        let sessionAID = UUID()
        let sessionBID = UUID()
        let sessionCID = UUID()

        var plan = try PlanEngine.apply(
            PlanMutation(
                operations: [
                    .addSession(id: sessionAID, name: "A", index: nil),
                    .addSession(id: sessionBID, name: "B", index: nil),
                    .addSession(id: sessionCID, name: "C", index: nil),
                ], summary: nil),
            to: PlanEngine.empty(name: "Plan"))

        // No cursor set ⇒ falls back to the first session.
        XCTAssertEqual(plan.nextSession?.id, sessionAID)

        // Advance the cursor to B.
        plan = try PlanEngine.apply(
            PlanMutation(operations: [.setCursor(sessionID: sessionBID)], summary: nil), to: plan)
        XCTAssertEqual(plan.nextSession?.id, sessionBID)

        // Advance again to C.
        plan = try PlanEngine.apply(
            PlanMutation(operations: [.setCursor(sessionID: sessionCID)], summary: nil), to: plan)
        XCTAssertEqual(plan.nextSession?.id, sessionCID)

        // Unknown cursor target throws and doesn't change anything.
        let unknown = UUID()
        XCTAssertThrowsError(
            try PlanEngine.apply(
                PlanMutation(operations: [.setCursor(sessionID: unknown)], summary: nil), to: plan)
        ) { error in
            XCTAssertEqual(error as? PlanEngineError, .unknownID(unknown))
        }
    }

    func testRemovingTheCursorSessionAdvancesToWhatWasNextClampedOrClearsIfNoneRemain() throws {
        let sessionAID = UUID()
        let sessionBID = UUID()
        let sessionCID = UUID()

        var plan = try PlanEngine.apply(
            PlanMutation(
                operations: [
                    .addSession(id: sessionAID, name: "A", index: nil),
                    .addSession(id: sessionBID, name: "B", index: nil),
                    .addSession(id: sessionCID, name: "C", index: nil),
                    .setCursor(sessionID: sessionBID),
                ], summary: nil),
            to: PlanEngine.empty(name: "Plan"))

        // Removing the cursor session (B, middle) advances the cursor to whatever now occupies that
        // index — C, which was "next after" B.
        plan = try PlanEngine.apply(
            PlanMutation(operations: [.removeSession(id: sessionBID)], summary: nil), to: plan)
        XCTAssertEqual(plan.sessions.map(\.id), [sessionAID, sessionCID])
        XCTAssertEqual(plan.cursorSessionID, sessionCID)

        // Removing the cursor session when it's now the last one clamps to the new last session.
        plan = try PlanEngine.apply(
            PlanMutation(operations: [.removeSession(id: sessionCID)], summary: nil), to: plan)
        XCTAssertEqual(plan.sessions.map(\.id), [sessionAID])
        XCTAssertEqual(plan.cursorSessionID, sessionAID)

        // Removing the last remaining session clears the cursor entirely.
        plan = try PlanEngine.apply(
            PlanMutation(operations: [.removeSession(id: sessionAID)], summary: nil), to: plan)
        XCTAssertEqual(plan.sessions, [])
        XCTAssertNil(plan.cursorSessionID)
        XCTAssertNil(plan.nextSession)
    }

    // MARK: - Additional engine behavior

    func testIndexOutOfRangeThrowsButIndexEqualToCountAppends() throws {
        let sessionID = UUID()
        let plan = try PlanEngine.apply(
            PlanMutation(operations: [.addSession(id: sessionID, name: "Day 1", index: nil)], summary: nil),
            to: PlanEngine.empty(name: "Plan"))

        // index == count (0 blocks so far) is a valid append, not an error.
        let blockID = UUID()
        let appended = try PlanEngine.apply(
            PlanMutation(
                operations: [
                    .addBlock(
                        sessionID: sessionID,
                        block: BlockSnapshot(
                            id: blockID, kind: .straight, label: "Bench", rounds: 1, restSeconds: nil,
                            exercises: []),
                        index: 0)
                ], summary: nil),
            to: plan)
        XCTAssertEqual(appended.findSession(sessionID)?.blocks.count, 1)

        // index beyond count throws.
        XCTAssertThrowsError(
            try PlanEngine.apply(
                PlanMutation(
                    operations: [
                        .addBlock(
                            sessionID: sessionID,
                            block: BlockSnapshot(
                                id: UUID(), kind: .straight, label: "Squat", rounds: 1,
                                restSeconds: nil, exercises: []),
                            index: 5)
                    ], summary: nil),
                to: appended)
        ) { error in
            XCTAssertEqual(error as? PlanEngineError, .indexOutOfRange)
        }
    }

    func testSetPlanMetaRejectsClearingOrEmptyingTheRequiredName() {
        let plan = PlanEngine.empty(name: "Plan")

        XCTAssertThrowsError(
            try PlanEngine.apply(
                PlanMutation(
                    operations: [.setPlanMeta(name: .clear, goal: .keep, notes: .keep)], summary: nil),
                to: plan)
        ) { error in
            XCTAssertEqual(error as? PlanEngineError, .emptyPlanName)
        }

        XCTAssertThrowsError(
            try PlanEngine.apply(
                PlanMutation(
                    operations: [.setPlanMeta(name: .set("   "), goal: .keep, notes: .keep)],
                    summary: nil),
                to: plan)
        ) { error in
            XCTAssertEqual(error as? PlanEngineError, .emptyPlanName)
        }
    }

    func testSummarizeProducesATerseHumanSummary() {
        let benchID = UUID()
        let setID = UUID()
        let mutation = PlanMutation(
            operations: [
                .addExercise(
                    blockID: UUID(),
                    exercise: ExerciseSnapshot(id: benchID, name: "Bench Press", cue: "", sets: []),
                    index: nil),
                .removeSet(id: setID),
            ],
            summary: nil
        )
        XCTAssertEqual(PlanEngine.summarize(mutation), "Added Bench Press; removed 1 set")
    }
}
