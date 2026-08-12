import XCTest
import SwiftData
@testable import WorkoutMD

/// Unit tests for onboarding's completion invariant (domain-primitives.md §9): onboarding is
/// complete when an active plan exists, or the user explicitly opts out — never merely because a
/// slide/screen was dismissed. Driving the real LLM isn't possible in a unit test, so these exercise
/// the completion logic (`OnboardingCompletion.isComplete`, the exact condition `OnboardingView`'s
/// "You're set" button keys on) against the one real path that produces an active plan in product
/// code: the coach's `plan_apply` tool (via `AppCoachHost`, mirroring `AppCoachHostTests`). There is
/// no hardcoded "sample plan" starter in the app anymore — `DefaultPlanSeed` is a test-only fixture
/// (`DefaultPlanSeedFixture.swift`) used elsewhere to build a concrete plan quickly, not a reachable
/// product flow.
final class OnboardingCompletionTests: XCTestCase {

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

    private func activePlans(_ context: ModelContext) throws -> [PlanRecord] {
        let descriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.isActive == true })
        return try context.fetch(descriptor)
    }

    /// Mirrors `AppCoachHostTests.callApplyTool`: `applyTool` hops onto the main thread via
    /// `DispatchQueue.main.sync`, so calling it directly from the (already-main) test thread would
    /// deadlock. Runs the call on a background queue and pumps the run loop while waiting.
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

    // MARK: - 1. No active plan ⇒ onboarding is NOT complete

    func testWithNoActivePlanCompletionConditionIsFalse() throws {
        let context = try makeContext()
        XCTAssertFalse(OnboardingCompletion.isComplete(activePlans: try activePlans(context)))
    }

    // MARK: - 2. Coach's plan_apply (no prior active plan) ⇒ an active plan now exists

    func testPlanApplyWithNoPriorActivePlanSatisfiesCompletionCondition() throws {
        let context = try makeContext()
        XCTAssertTrue(try activePlans(context).isEmpty, "precondition: nothing active yet")

        let host = AppCoachHost(modelContext: context)
        let sessionID = UUID()
        let blockID = UUID()
        let exerciseID = UUID()
        let setID = UUID()
        let argsJson = """
        {"operations":[
          {"op":"setPlanMeta","name":"Push/Pull/Legs"},
          {"op":"addSession","id":"\(sessionID.uuidString)","name":"Push"},
          {"op":"addBlock","sessionID":"\(sessionID.uuidString)","block":{"id":"\(blockID.uuidString)","kind":"straight","label":"Bench Press","rounds":1,"restSeconds":null,"exercises":[{"id":"\(exerciseID.uuidString)","name":"Bench Press","cue":"Elbows tucked","sets":[{"id":"\(setID.uuidString)","reps":8,"weight":135,"seconds":null}]}]}}
        ]}
        """

        let confirmation = callApplyTool(host, name: "plan_apply", argsJson: argsJson)
        XCTAssertTrue(confirmation.contains("Created and activated plan"), confirmation)

        let plans = try activePlans(context)
        XCTAssertEqual(plans.count, 1)
        XCTAssertTrue(OnboardingCompletion.isComplete(activePlans: plans), "an active plan now exists — the 'You're set' condition")
    }
}
