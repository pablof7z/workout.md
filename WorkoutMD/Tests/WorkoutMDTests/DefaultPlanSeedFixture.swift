import Foundation
@testable import WorkoutMD

/// TEST-ONLY fixture (`Tests/WorkoutMDTests`, `@testable import WorkoutMD`) — a small, real
/// `PlanRecord` graph used by unit tests that need a concrete plan to exercise
/// (`ActiveSessionTests`, `OnboardingCompletionTests`, `PlanRepositoryTests`) without hand-building
/// one inline every time. This is deliberately NOT reachable from app/product code: there is no
/// hardcoded starter plan in the shipping app — every real plan comes from the coach's `plan_apply`
/// tool (domain-primitives.md §9, invariants 1/2). Content mirrors the prototype's old hardcoded
/// "Upper Body A" workout, kept only as a convenient test double.
enum DefaultPlanSeed {
    static func makePlanRecord() -> PlanRecord {
        let plan = PlanRecord(name: "Upper Body A", goal: "Hypertrophy", isActive: true)

        let session = PlanSessionRecord(order: 0, name: "Workout")
        session.plan = plan
        plan.sessions = [session]
        plan.nextSessionID = session.id

        let bench = PlanBlockRecord(order: 0, kind: .straight, label: "Bench Press", sessionID: session.id)
        let benchExercise = PlanExerciseRecord(order: 0, name: "Bench Press", cue: "Control the eccentric, 2s down. Leave 2 in the tank.")
        benchExercise.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 10, weight: 135) }
        bench.exercises = [benchExercise]

        let supersetA = PlanBlockRecord(order: 1, kind: .superset, label: "Superset A", rounds: 3, restSeconds: 60, sessionID: session.id)
        let inclineDB = PlanExerciseRecord(order: 0, name: "Incline DB Press", cue: "Squeeze at the top. Stop 1–2 reps short.")
        inclineDB.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 12, weight: 50) }
        let row = PlanExerciseRecord(order: 1, name: "Barbell Row", cue: "Flat back. Drive elbows to hips.")
        row.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 10, weight: 135) }
        supersetA.exercises = [inclineDB, row]

        let circuit = PlanBlockRecord(order: 2, kind: .circuit, label: "Circuit", rounds: 3, restSeconds: 45, sessionID: session.id)
        let facePull = PlanExerciseRecord(order: 0, name: "Face Pull", cue: "High elbows, pull to the eyes.")
        facePull.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 15, weight: nil) }
        let cableFly = PlanExerciseRecord(order: 1, name: "Cable Fly", cue: "Long arc, feel the stretch.")
        cableFly.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 12, weight: nil) }
        let plank = PlanExerciseRecord(order: 2, name: "Plank", cue: "Ribs down, glutes tight.")
        plank.sets = (0..<3).map { PlanSetRecord(order: $0, seconds: 45) }
        circuit.exercises = [facePull, cableFly, plank]

        plan.blocks = [bench, supersetA, circuit]
        return plan
    }
}
