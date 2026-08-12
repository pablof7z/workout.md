import XCTest
import SwiftData
@testable import WorkoutMD

/// Unit tests for the SwiftData persistence layer built on top of the canonical plan value layer:
/// `PlanRepository` (create/apply/propose/revisions/restore), `PlanReconciler` (upsert-by-UUID
/// identity-stable diff), and `PlanMigrator` (idempotent legacy-plan session backfill). Uses an
/// in-memory `ModelContainer` — see `makeContext()` — so every test starts from a clean store.
/// `@testable import WorkoutMD` is required because these types live on `PlanRecord`, which
/// transitively pulls in the whole app (see the doc comment on `PlanEngineTests`).
final class PlanRepositoryTests: XCTestCase {

    // MARK: - Fixture

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutRecord.self,
            ExerciseRecord.self,
            SetRecord.self,
            CoachNoteRecord.self,
            PlanRecord.self,
            PlanBlockRecord.self,
            PlanExerciseRecord.self,
            PlanSetRecord.self,
            PlanSessionRecord.self,
            PlanRevisionRecord.self
        ])
        // `cloudKitDatabase: .none` mirrors `WorkoutMDApp`'s own container: this test bundle links
        // against the app target (and its iCloud entitlement), so without this SwiftData detects the
        // capability and tries to validate this schema against CloudKit's stricter constraints
        // (all-optional attributes/relationships, no unique constraints) — which this schema
        // intentionally doesn't satisfy, the same way the real app's container doesn't.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// A small, self-contained mutation that builds a one-session, one-block, one-exercise,
    /// two-set plan from empty — the same "create by mutation" shape `PlanEngineTests` exercises.
    private func buildMutation(
        sessionID: UUID = UUID(), blockID: UUID = UUID(), exerciseID: UUID = UUID(),
        set1ID: UUID = UUID(), set2ID: UUID = UUID()
    ) -> PlanMutation {
        PlanMutation(
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
                        id: exerciseID, name: "Bench Press", cue: "Elbows tucked", sets: []),
                    index: nil),
                .addSet(
                    exerciseID: exerciseID,
                    set: SetSnapshot(id: set1ID, reps: 8, weight: 135, seconds: nil), index: nil),
                .addSet(
                    exerciseID: exerciseID,
                    set: SetSnapshot(id: set2ID, reps: 8, weight: 135, seconds: nil), index: nil),
                .setCursor(sessionID: sessionID),
            ],
            summary: nil
        )
    }

    // MARK: - 1. createPlan

    func testCreatePlanByApplyingMutationsToEmptyBuildsMatchingGraphAndSnapshot() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let sessionID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()

        let plan = try repository.createPlan(
            buildMutation(sessionID: sessionID, blockID: blockID, exerciseID: exerciseID),
            name: "Upper/Lower", activate: true
        )

        XCTAssertTrue(plan.isActive)
        XCTAssertEqual(plan.orderedSessions.count, 1)
        XCTAssertEqual(plan.orderedSessions.first?.id, sessionID)
        XCTAssertEqual(plan.nextSessionID, sessionID)
        XCTAssertEqual(plan.orderedBlocks.count, 1)
        XCTAssertEqual(plan.orderedBlocks.first?.id, blockID)
        XCTAssertEqual(plan.orderedBlocks.first?.sessionID, sessionID)
        XCTAssertEqual(plan.orderedBlocks.first?.orderedExercises.first?.id, exerciseID)
        XCTAssertEqual(plan.orderedBlocks.first?.orderedExercises.first?.orderedSets.count, 2)

        let snapshot = plan.toSnapshot()
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions.first?.blocks.first?.exercises.first?.sets.count, 2)
        XCTAssertEqual(snapshot.cursorSessionID, sessionID)
    }

    func testCreatePlanWithoutActivateDoesNotActivate() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)

        let plan = try repository.createPlan(buildMutation(), name: "Draft", activate: false)

        XCTAssertFalse(plan.isActive)
    }

    func testAcceptProposalCreatesDistinctPlanAndActivatesOnlyAfterAcceptance() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let existing = try repository.createPlan(buildMutation(), name: "Existing", activate: true)
        let existingSnapshot = existing.toSnapshot()
        var proposal = try PlanEngine.apply(
            PlanMutation(
                operations: [.setPlanMeta(name: .set("Coach Plan"), goal: .set("Grip strength"), notes: .set("Use Tindeq"))],
                summary: "Coach proposal"
            ),
            to: existingSnapshot
        )
        proposal.id = existing.id

        XCTAssertTrue(existing.isActive)
        XCTAssertEqual(existing.name, "Existing")

        let accepted = try repository.acceptProposal(proposal)

        XCTAssertNotEqual(accepted.id, existing.id)
        XCTAssertEqual(accepted.name, "Coach Plan")
        XCTAssertTrue(accepted.isActive)
        XCTAssertFalse(existing.isActive)
        XCTAssertEqual(existing.name, "Existing", "accepting creates a new plan rather than rewriting the prior one")
        XCTAssertNotEqual(accepted.orderedSessions.first?.id, existing.orderedSessions.first?.id)
        XCTAssertEqual(repository.revisions(of: accepted.id).first?.summary, "Accepted coach proposal")
    }

    // MARK: - 2. apply (default mode)

    func testApplyMutationInDefaultModeReconcilesGraphAndWritesRevision() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let plan = try repository.createPlan(buildMutation(), name: "Upper A", activate: true)
        XCTAssertEqual(repository.revisions(of: plan.id).count, 1, "createPlan writes a baseline revision")

        let exerciseID = UUID()
        let setID = UUID()
        guard let blockID = plan.orderedBlocks.first?.id else { return XCTFail("expected a block") }
        let addExercise = PlanMutation(
            operations: [
                .addExercise(
                    blockID: blockID,
                    exercise: ExerciseSnapshot(id: exerciseID, name: "Incline Press", cue: "", sets: []),
                    index: nil),
                .addSet(exerciseID: exerciseID, set: SetSnapshot(id: setID, reps: 10, weight: 60, seconds: nil), index: nil),
            ],
            summary: "Added Incline Press"
        )

        let result = try repository.apply(addExercise, to: plan.id)

        XCTAssertFalse(result.proposed)
        XCTAssertNotNil(result.revisionID)
        XCTAssertEqual(result.snapshot.sessions.first?.blocks.first?.exercises.count, 2)

        // Reconciled graph reflects the change.
        let refreshedBlock = plan.orderedBlocks.first { $0.id == blockID }
        XCTAssertEqual(refreshedBlock?.orderedExercises.count, 2)
        XCTAssertTrue(refreshedBlock?.orderedExercises.contains { $0.id == exerciseID } ?? false)

        // A revision was written.
        let revisions = repository.revisions(of: plan.id)
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(revisions.first?.summary, "Added Incline Press")

        // Snapshot round-trips through the stored graph.
        XCTAssertEqual(plan.toSnapshot(), result.snapshot)
    }

    // MARK: - 3. propose mode

    func testProposeModeReturnsCandidateWithoutMutatingStoredGraphOrWritingARevision() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let plan = try repository.createPlan(buildMutation(), name: "Upper A", activate: true)
        let revisionCountBefore = repository.revisions(of: plan.id).count
        let blockCountBefore = plan.blocks.count

        guard let blockID = plan.orderedBlocks.first?.id else { return XCTFail("expected a block") }
        let mutation = PlanMutation(
            operations: [
                .addExercise(
                    blockID: blockID,
                    exercise: ExerciseSnapshot(id: UUID(), name: "Incline Press", cue: "", sets: []),
                    index: nil)
            ],
            summary: nil
        )

        let result = try repository.apply(mutation, to: plan.id, mode: .propose)

        XCTAssertTrue(result.proposed)
        XCTAssertNil(result.revisionID)
        XCTAssertEqual(result.snapshot.sessions.first?.blocks.first?.exercises.count, 2)

        // Stored graph is untouched.
        XCTAssertEqual(plan.blocks.count, blockCountBefore)
        XCTAssertEqual(plan.orderedBlocks.first?.orderedExercises.count, 1)
        XCTAssertEqual(repository.revisions(of: plan.id).count, revisionCountBefore)
    }

    // MARK: - 4. revisions + restore

    func testRevisionsAreListedNewestFirstAndRestoreCreatesANewVersionedRevision() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let plan = try repository.createPlan(buildMutation(), name: "Upper A", activate: true)
        let baselineSnapshot = plan.toSnapshot()
        guard let baselineRevision = repository.revisions(of: plan.id).first else {
            return XCTFail("expected a baseline revision")
        }

        guard let blockID = plan.orderedBlocks.first?.id else { return XCTFail("expected a block") }
        _ = try repository.apply(
            PlanMutation(
                operations: [
                    .addExercise(
                        blockID: blockID,
                        exercise: ExerciseSnapshot(id: UUID(), name: "Incline Press", cue: "", sets: []),
                        index: nil)
                ],
                summary: "Added Incline Press"
            ),
            to: plan.id
        )

        let revisionsAfterEdit = repository.revisions(of: plan.id)
        XCTAssertEqual(revisionsAfterEdit.count, 2)
        XCTAssertEqual(revisionsAfterEdit.first?.summary, "Added Incline Press", "newest first")
        XCTAssertEqual(plan.orderedBlocks.first?.orderedExercises.count, 2)

        let restoreResult = try repository.restore(revisionID: baselineRevision.id)

        XCTAssertEqual(restoreResult.snapshot, baselineSnapshot)
        XCTAssertEqual(plan.orderedBlocks.first?.orderedExercises.count, 1, "restored to the baseline")
        XCTAssertEqual(plan.toSnapshot(), baselineSnapshot)

        // Restore is itself a versioned change: a NEW revision was written, not a rewind in place.
        let revisionsAfterRestore = repository.revisions(of: plan.id)
        XCTAssertEqual(revisionsAfterRestore.count, 3)
        XCTAssertNotEqual(revisionsAfterRestore.first?.id, baselineRevision.id)
    }

    // MARK: - 5. Reconcile stable identity

    /// "Stable identity" is asserted via `persistentModelID` (SwiftData's own durable per-row
    /// identity — what `@Query` diffing actually keys on), not raw `ObjectIdentifier`/Swift-object
    /// pointer equality: SwiftData is free to re-materialize a fresh Swift proxy instance for an
    /// already-persisted row when a relationship is re-traversed after a fetch/save (observed
    /// directly against this schema — the wrapper instance can change even though it is provably the
    /// same underlying row), so `ObjectIdentifier` is not a reliable signal here. `persistentModelID`
    /// staying constant is exactly the "upsert in place, not delete-and-reinsert" guarantee this test
    /// is meant to cover.
    func testReconcileUpdatingOneSetLeavesSiblingRecordIdentityUnchanged() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let sessionID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let set1ID = UUID()
        let set2ID = UUID()
        let plan = try repository.createPlan(
            buildMutation(sessionID: sessionID, blockID: blockID, exerciseID: exerciseID, set1ID: set1ID, set2ID: set2ID),
            name: "Upper A", activate: true
        )

        let exerciseBefore = plan.orderedBlocks.first?.orderedExercises.first
        let sibling = exerciseBefore?.orderedSets.first { $0.id == set2ID }
        XCTAssertNotNil(sibling)
        let siblingPID = sibling!.persistentModelID
        let sessionPID = plan.orderedSessions.first!.persistentModelID
        let blockPID = plan.orderedBlocks.first!.persistentModelID
        let exercisePID = exerciseBefore!.persistentModelID

        _ = try repository.apply(
            PlanMutation(
                operations: [.updateSet(
                    id: set1ID, reps: .set(12), weight: .keep, seconds: .keep,
                    targetMinKg: .keep, targetMaxKg: .keep)],
                summary: nil
            ),
            to: plan.id
        )

        let exerciseAfter = plan.orderedBlocks.first?.orderedExercises.first
        let siblingAfter = exerciseAfter?.orderedSets.first { $0.id == set2ID }
        let updated = exerciseAfter?.orderedSets.first { $0.id == set1ID }

        XCTAssertEqual(updated?.reps, 12)
        XCTAssertNotNil(siblingAfter)
        XCTAssertEqual(siblingAfter!.persistentModelID, siblingPID, "sibling set's identity is preserved")
        XCTAssertEqual(exerciseAfter!.persistentModelID, exercisePID, "exercise identity is preserved")
        XCTAssertEqual(plan.orderedBlocks.first!.persistentModelID, blockPID, "block identity is preserved")
        XCTAssertEqual(plan.orderedSessions.first!.persistentModelID, sessionPID, "session identity is preserved")
    }

    // MARK: - 6. Migration / backfill

    /// Builds a legacy-shaped `PlanRecord` directly (bypassing `PlanRepository`/`DefaultPlanSeed`,
    /// both of which already stamp sessions) — blocks with `sessionID == nil` and no sessions, the
    /// shape a pre-existing store has before this slice.
    private func makeLegacyPlan(context: ModelContext) -> PlanRecord {
        let plan = PlanRecord(name: "Legacy Plan", goal: "Strength", isActive: true)
        let block = PlanBlockRecord(order: 0, kind: .straight, label: "Bench Press")
        let exercise = PlanExerciseRecord(order: 0, name: "Bench Press", cue: "")
        exercise.sets = [PlanSetRecord(order: 0, reps: 8, weight: 135)]
        block.exercises = [exercise]
        plan.blocks = [block]
        context.insert(plan)
        try? context.save()
        return plan
    }

    func testMigratorBackfillsExactlyOneSessionAndStampsBlocksAndWritesBaselineRevision() throws {
        let context = try makeContext()
        let legacy = makeLegacyPlan(context: context)

        // Unrelated history must be untouched by the backfill.
        let historyRecord = WorkoutRecord(date: .now, name: "Past Session", goal: nil)
        context.insert(historyRecord)
        try context.save()

        PlanMigrator.backfill(context: context)

        XCTAssertEqual(legacy.sessions.count, 1)
        let session = try XCTUnwrap(legacy.sessions.first)
        XCTAssertEqual(legacy.nextSessionID, session.id)
        XCTAssertTrue(legacy.blocks.allSatisfy { $0.sessionID == session.id })

        let repository = PlanRepository(context: context)
        let revisions = repository.revisions(of: legacy.id)
        XCTAssertEqual(revisions.count, 1)
        XCTAssertEqual(revisions.first?.summary, "Imported existing plan")

        // History is untouched.
        let historyDescriptor = FetchDescriptor<WorkoutRecord>()
        let history = try context.fetch(historyDescriptor)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.name, "Past Session")
    }

    func testMigratorBackfillIsIdempotent() throws {
        let context = try makeContext()
        let legacy = makeLegacyPlan(context: context)

        PlanMigrator.backfill(context: context)
        let sessionAfterFirstRun = try XCTUnwrap(legacy.sessions.first)
        let repository = PlanRepository(context: context)
        let revisionCountAfterFirstRun = repository.revisions(of: legacy.id).count

        PlanMigrator.backfill(context: context)

        XCTAssertEqual(legacy.sessions.count, 1, "running backfill twice does not create a second session")
        XCTAssertEqual(legacy.sessions.first?.id, sessionAfterFirstRun.id)
        XCTAssertEqual(repository.revisions(of: legacy.id).count, revisionCountAfterFirstRun, "no duplicate baseline revision")
    }
}
