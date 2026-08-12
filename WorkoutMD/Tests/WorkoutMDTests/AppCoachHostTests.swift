import XCTest
import SwiftData
@testable import WorkoutMD

/// Unit tests for `AppCoachHost` — the general `CoachHost` that dispatches the nine Slice 3a tools
/// (`plan_get`/`plan_apply`/`plan_revisions`/`plan_restore`/`memory_add`/`memory_update`/
/// `memory_query`/`memory_remove`/`session_apply`) to `PlanRepository`/`MemoryStore`/the live
/// `WorkoutSession`. No LLM involved — every test drives `apply_tool(name:argsJson:)` directly with
/// hand-built JSON, the same wire shape `core/workout-core/src/coach/tools.rs` sends. Uses an
/// in-memory `ModelContainer` (mirrors `PlanRepositoryTests`/`MemoryStoreTests`) so every test
/// starts from a clean store.
///
/// `apply_tool` hops onto the main thread with `DispatchQueue.main.sync` (matching the production
/// `CoachHost.applyTool` contract — see `AppCoachHost`'s doc comment): calling it directly from an
/// XCTest method, which itself runs on the main thread, would deadlock (the main thread would be
/// blocked waiting on itself). `callApplyTool` below avoids this the same way the task calls for:
/// it runs the host call on a background utility queue and blocks the test via an
/// `XCTestExpectation`/`wait(for:timeout:)`, which pumps the run loop while waiting — unlike a bare
/// semaphore wait — so the `DispatchQueue.main.sync` hop back onto the (still-idle) main thread can
/// actually execute.
final class AppCoachHostTests: XCTestCase {

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
            PlanRevisionRecord.self,
            MemoryRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// Calls `host.applyTool` off the main thread and waits for it via the run-loop-pumping
    /// `wait(for:timeout:)` — see the class doc comment for why a bare synchronous wait would
    /// deadlock against `apply_tool`'s own `DispatchQueue.main.sync`.
    private func callApplyTool(_ host: AppCoachHost, name: String, argsJson: String) -> String {
        let done = expectation(description: "apply_tool(\(name))")
        var result = ""
        DispatchQueue.global(qos: .utility).async {
            result = host.applyTool(name: name, argsJson: argsJson)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    /// A small, self-contained mutation that builds a one-session, one-block, one-exercise,
    /// one-set plan from empty — mirrors `PlanRepositoryTests`' fixture shape.
    private static func buildMutation() -> PlanMutation {
        let sessionID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        return PlanMutation(
            operations: [
                .addSession(id: sessionID, name: "Upper A", index: nil),
                .addBlock(
                    sessionID: sessionID,
                    block: BlockSnapshot(id: blockID, kind: .straight, label: "Bench Press", rounds: 1, restSeconds: nil, exercises: []),
                    index: nil),
                .addExercise(
                    blockID: blockID,
                    exercise: ExerciseSnapshot(id: exerciseID, name: "Bench Press", cue: "Elbows tucked", sets: []),
                    index: nil),
                .addSet(exerciseID: exerciseID, set: SetSnapshot(id: UUID(), reps: 8, weight: 135, seconds: nil), index: nil),
                .setCursor(sessionID: sessionID),
            ],
            summary: nil
        )
    }

    /// A minimal live `WorkoutSession` — one straight-sets exercise, two prescribed sets — with
    /// real, stable `WorkoutStep.id`s to address via `session_apply`.
    private static func makeFixtureSession() -> WorkoutSession {
        func step(setNumber: Int) -> WorkoutStep {
            let exercise = Exercise(name: "Bench Press", cue: "Elbows tucked", target: .reps(count: 8, weight: 135), moodKey: .bench)
            let info = SetPageInfo(
                exercise: exercise, setNumber: setNumber, totalSets: 2,
                groupLabel: nil, groupKind: nil, round: nil, totalRounds: nil, miniMap: nil
            )
            return WorkoutStep(blockIndex: 0, blockName: "Bench Press", moodKey: .bench, page: .set(info), exerciseName: "Bench Press")
        }
        return WorkoutSession(steps: [step(setNumber: 1), step(setNumber: 2)])
    }

    // MARK: - 1. plan_apply — create when no active plan

    func testPlanApplyCreatesAndActivatesPlanWhenNoneActive() throws {
        let context = try makeContext()
        let host = AppCoachHost(modelContext: context)

        let sessionID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let setID = UUID()
        let argsJson = """
        {"operations":[
          {"op":"setPlanMeta","name":"Upper/Lower"},
          {"op":"addSession","id":"\(sessionID.uuidString)","name":"Upper A"},
          {"op":"addBlock","sessionID":"\(sessionID.uuidString)","block":{"id":"\(blockID.uuidString)","kind":"straight","label":"Bench Press","rounds":1,"restSeconds":null,"exercises":[{"id":"\(exerciseID.uuidString)","name":"Bench Press","cue":"Elbows tucked","sets":[{"id":"\(setID.uuidString)","reps":8,"weight":135,"seconds":null}]}]}}
        ]}
        """

        let confirmation = callApplyTool(host, name: "plan_apply", argsJson: argsJson)
        XCTAssertTrue(confirmation.contains("Created and activated plan"), confirmation)

        let repository = PlanRepository(context: context)
        let snapshot = try XCTUnwrap(repository.activeSnapshot())
        XCTAssertEqual(snapshot.name, "Upper/Lower")
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions.first?.blocks.first?.exercises.first?.name, "Bench Press")
        XCTAssertEqual(snapshot.sessions.first?.blocks.first?.exercises.first?.sets.count, 1)

        // A plan record was actually created and activated, not just an in-memory snapshot.
        var descriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.isActive == true })
        let activePlans = try context.fetch(descriptor)
        XCTAssertEqual(activePlans.count, 1)
        XCTAssertEqual(activePlans.first?.id, snapshot.id)

        XCTAssertEqual(repository.revisions(of: snapshot.id).count, 1, "createPlan writes a baseline revision")
    }

    // MARK: - 2. plan_apply — edit when a plan is active

    func testPlanApplyEditsActivePlanAndWritesNewRevision() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let plan = try repository.createPlan(Self.buildMutation(), name: "Upper A", activate: true)
        let blockID = try XCTUnwrap(plan.orderedBlocks.first?.id)
        let revisionCountBefore = repository.revisions(of: plan.id).count

        let host = AppCoachHost(modelContext: context)
        let argsJson = """
        {"operations":[{"op":"addExercise","blockID":"\(blockID.uuidString)","exercise":{"id":"\(UUID().uuidString)","name":"Incline Press","cue":"","sets":[]}}],"summary":"Added Incline Press"}
        """

        let confirmation = callApplyTool(host, name: "plan_apply", argsJson: argsJson)
        XCTAssertTrue(confirmation.contains("Applied"), confirmation)

        let snapshot = try XCTUnwrap(repository.activeSnapshot())
        XCTAssertEqual(snapshot.sessions.first?.blocks.first?.exercises.count, 2)
        XCTAssertEqual(repository.revisions(of: plan.id).count, revisionCountBefore + 1)
        XCTAssertEqual(repository.revisions(of: plan.id).first?.summary, "Added Incline Press")
    }

    func testPlanApplyCanCreateAndConvertTindeqSets() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let plan = try repository.createPlan(Self.buildMutation(), name: "Grip", activate: true)
        let blockID = try XCTUnwrap(plan.orderedBlocks.first?.id)
        let existingSetID = try XCTUnwrap(plan.orderedBlocks.first?.orderedExercises.first?.orderedSets.first?.id)
        let exerciseID = UUID()
        let tindeqSetID = UUID()
        let host = AppCoachHost(modelContext: context)
        let argsJson = """
        {"operations":[
          {"op":"addExercise","blockID":"\(blockID.uuidString)","exercise":{"id":"\(exerciseID.uuidString)","name":"Half Crimp","cue":"Shoulder engaged","sets":[{"id":"\(tindeqSetID.uuidString)","reps":null,"weight":null,"seconds":7,"targetMinKg":30,"targetMaxKg":34}]}},
          {"op":"updateSet","id":"\(existingSetID.uuidString)","reps":null,"weight":null,"seconds":10,"targetMinKg":20,"targetMaxKg":25}
        ],"summary":"Added Tindeq hangs"}
        """

        let confirmation = callApplyTool(host, name: "plan_apply", argsJson: argsJson)

        XCTAssertTrue(confirmation.contains("Applied"), confirmation)
        let snapshot = try XCTUnwrap(repository.activeSnapshot())
        let created = try XCTUnwrap(snapshot.findSet(tindeqSetID)?.set)
        XCTAssertEqual(created.seconds, 7)
        XCTAssertEqual(created.targetMinKg, 30)
        XCTAssertEqual(created.targetMaxKg, 34)
        let converted = try XCTUnwrap(snapshot.findSet(existingSetID)?.set)
        XCTAssertNil(converted.reps)
        XCTAssertNil(converted.weight)
        XCTAssertEqual(converted.seconds, 10)
        XCTAssertEqual(converted.targetMinKg, 20)
        XCTAssertEqual(converted.targetMaxKg, 25)
    }

    // MARK: - 3. plan_apply — propose

    func testPlanApplyProposeReturnsProposalWithoutMutatingStoredPlan() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let plan = try repository.createPlan(Self.buildMutation(), name: "Upper A", activate: true)
        let blockID = try XCTUnwrap(plan.orderedBlocks.first?.id)
        let exerciseCountBefore = plan.orderedBlocks.first?.orderedExercises.count
        let revisionCountBefore = repository.revisions(of: plan.id).count

        let host = AppCoachHost(modelContext: context)
        let argsJson = """
        {"operations":[{"op":"addExercise","blockID":"\(blockID.uuidString)","exercise":{"id":"\(UUID().uuidString)","name":"Incline Press","cue":"","sets":[]}}],"propose":true}
        """

        let confirmation = callApplyTool(host, name: "plan_apply", argsJson: argsJson)
        XCTAssertTrue(confirmation.hasPrefix("Proposed (not applied):"), confirmation)

        XCTAssertEqual(plan.orderedBlocks.first?.orderedExercises.count, exerciseCountBefore, "propose does not touch the stored graph")
        XCTAssertEqual(repository.revisions(of: plan.id).count, revisionCountBefore, "propose does not write a revision")
    }

    func testPlanningHostBuildsVisibleProposalWithoutChangingActivePlanOrLeakingReadJSON() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let active = try repository.createPlan(Self.buildMutation(), name: "Existing Plan", activate: true)
        let existingSnapshot = active.toSnapshot()
        var proposal: PlanSnapshot?
        var visibleDiffs: [String] = []
        let host = AppCoachHost(
            modelContext: context,
            planToolBehavior: .buildProposal(nil),
            onPlanProposal: { proposal = $0 },
            onDiff: { visibleDiffs.append($0) }
        )

        let emptyRead = callApplyTool(host, name: "plan_get", argsJson: "{}")
        XCTAssertTrue(emptyRead.contains("No active plan yet"), emptyRead)
        XCTAssertTrue(visibleDiffs.isEmpty, "machine-readable plan_get output must stay out of the transcript")

        let mutation = Self.buildMutation()
        let encoded = try JSONEncoder().encode(mutation.operations)
        let operationsJSON = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let result = callApplyTool(
            host,
            name: "plan_apply",
            argsJson: #"{"operations":\#(operationsJSON),"summary":"Prepared a workout"}"#
        )

        XCTAssertTrue(result.contains("Prepared a plan proposal"), result)
        XCTAssertNotNil(proposal)
        XCTAssertEqual(proposal?.sessions.first?.name, "Upper A")
        XCTAssertEqual(active.toSnapshot(), existingSnapshot, "planning must not mutate the active plan")
        XCTAssertTrue(visibleDiffs.isEmpty, "the proposal renders as a structured card, not a tool-result line")
    }

    // MARK: - 4. memory_add / memory_query

    func testMemoryAddThenQueryViaHostReflectsInMemoryStore() throws {
        let context = try makeContext()
        let host = AppCoachHost(modelContext: context)

        let addConfirmation = callApplyTool(host, name: "memory_add", argsJson: #"{"text":"Prefers dumbbells over barbells","tags":["equipment"]}"#)
        XCTAssertTrue(addConfirmation.contains("Prefers dumbbells over barbells"), addConfirmation)
        XCTAssertEqual(MemoryStore(context: context).all().count, 1)

        let queryResult = callApplyTool(host, name: "memory_query", argsJson: #"{"query":"dumbbells"}"#)
        let data = try XCTUnwrap(queryResult.data(using: .utf8))
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?["text"] as? String, "Prefers dumbbells over barbells")
        XCTAssertEqual(parsed.first?["tags"] as? [String], ["equipment"])
    }

    // MARK: - 5. plan_restore

    func testPlanRestoreRoundTripsToAPriorRevision() throws {
        let context = try makeContext()
        let repository = PlanRepository(context: context)
        let plan = try repository.createPlan(Self.buildMutation(), name: "Upper A", activate: true)
        let baselineRevision = try XCTUnwrap(repository.revisions(of: plan.id).first)
        let blockID = try XCTUnwrap(plan.orderedBlocks.first?.id)

        _ = try repository.apply(
            PlanMutation(
                operations: [
                    .addExercise(blockID: blockID, exercise: ExerciseSnapshot(id: UUID(), name: "Incline Press", cue: "", sets: []), index: nil)
                ],
                summary: "Added Incline Press"
            ),
            to: plan.id
        )
        XCTAssertEqual(plan.orderedBlocks.first?.orderedExercises.count, 2)

        let host = AppCoachHost(modelContext: context)
        let argsJson = #"{"revision_id":"\#(baselineRevision.id.uuidString)"}"#
        let confirmation = callApplyTool(host, name: "plan_restore", argsJson: argsJson)
        XCTAssertTrue(confirmation.contains("Restored"), confirmation)

        XCTAssertEqual(plan.orderedBlocks.first?.orderedExercises.count, 1, "restored to the baseline")
        XCTAssertEqual(repository.revisions(of: plan.id).count, 3, "restore itself writes a new revision")
    }

    // MARK: - 6. session_apply

    func testSessionApplyAdjustSetAndSkipSetMutateLiveSteps() throws {
        let context = try makeContext()
        let session = Self.makeFixtureSession()
        let firstStepID = session.steps[0].id
        let secondStepID = session.steps[1].id

        let host = AppCoachHost(modelContext: context, session: session)
        let argsJson = """
        {"operations":[
          {"op":"adjustSet","setID":"\(firstStepID.uuidString)","reps":6,"weight":145},
          {"op":"skipSet","setID":"\(secondStepID.uuidString)"}
        ]}
        """

        let confirmation = callApplyTool(host, name: "session_apply", argsJson: argsJson)
        XCTAssertTrue(confirmation.contains("skipped"), confirmation)

        guard case .set(let firstInfo) = session.steps[0].page, case .reps(let count, let weight) = firstInfo.exercise.target else {
            return XCTFail("expected the first step to still be a reps set")
        }
        XCTAssertEqual(count, 6)
        XCTAssertEqual(weight, 145)

        guard case .set(let secondInfo) = session.steps[1].page else {
            return XCTFail("expected the second step to still be a set")
        }
        XCTAssertEqual(secondInfo.state, .skipped)
    }

    func testSessionApplyWithNoLiveSessionReturnsAClearError() throws {
        let context = try makeContext()
        let host = AppCoachHost(modelContext: context, session: nil)

        let confirmation = callApplyTool(host, name: "session_apply", argsJson: #"{"operations":[{"op":"skipSet","setID":"\#(UUID().uuidString)"}]}"#)

        XCTAssertEqual(confirmation, "No live workout to modify.")
    }

    // MARK: - 7. escalate_to_reasoning

    /// No LLM/`CoachController` involved here — just confirms the wiring `applyTool` promises: the
    /// tool call reaches `onEscalate` and hands back a non-empty confirmation string, the same shape
    /// every other tool follows. The actual escalation re-run (switching to the reasoning tier) is
    /// `CoachController.converse`'s job, exercised separately.
    func testEscalateToReasoningInvokesOnEscalateAndReturnsConfirmation() throws {
        let context = try makeContext()
        final class EscalationSpy: @unchecked Sendable {
            var wasCalled = false
        }
        let spy = EscalationSpy()
        let host = AppCoachHost(modelContext: context, onEscalate: { spy.wasCalled = true })

        let confirmation = callApplyTool(host, name: "escalate_to_reasoning", argsJson: "{}")

        XCTAssertTrue(spy.wasCalled)
        XCTAssertFalse(confirmation.isEmpty)
    }

    func testEscalateToReasoningWithReasonStillInvokesOnEscalate() throws {
        let context = try makeContext()
        final class EscalationSpy: @unchecked Sendable {
            var wasCalled = false
        }
        let spy = EscalationSpy()
        let host = AppCoachHost(modelContext: context, onEscalate: { spy.wasCalled = true })

        let confirmation = callApplyTool(host, name: "escalate_to_reasoning", argsJson: #"{"reason":"building a full plan"}"#)

        XCTAssertTrue(spy.wasCalled)
        XCTAssertFalse(confirmation.isEmpty)
    }

    // MARK: - 8. Malformed args

    func testMalformedArgsJSONReturnsAnErrorStringWithoutCrashing() throws {
        let context = try makeContext()
        let host = AppCoachHost(modelContext: context)

        let confirmation = callApplyTool(host, name: "plan_apply", argsJson: "not valid json")

        XCTAssertEqual(confirmation, "Could not parse plan_apply arguments.")
    }

    func testUnknownToolNameReturnsAnErrorStringWithoutCrashing() throws {
        let context = try makeContext()
        let host = AppCoachHost(modelContext: context)

        let confirmation = callApplyTool(host, name: "not_a_real_tool", argsJson: "{}")

        XCTAssertEqual(confirmation, "Unknown tool not_a_real_tool.")
    }
}
