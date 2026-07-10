import Foundation

/// The plan seeded on first run so the app never opens to an empty Plans list — a real, ordinary
/// default the user can edit, duplicate, or delete like any other `PlanRecord` (deliberately NOT
/// labeled "sample"/"mock": unlike `MockHistory`'s seeded past sessions, this is live, usable data,
/// not a demo). Content mirrors the prototype's original hardcoded "Upper Body A" workout, now
/// expressed as an editable `PlanRecord` graph instead of a hand-compiled Swift literal.
enum DefaultPlanSeed {
    static func makePlanRecord() -> PlanRecord {
        let plan = PlanRecord(name: "Upper Body A", goal: "Hypertrophy", isActive: true)

        let bench = PlanBlockRecord(order: 0, kind: .straight, label: "Bench Press")
        let benchExercise = PlanExerciseRecord(order: 0, name: "Bench Press", cue: "Control the eccentric, 2s down. Leave 2 in the tank.")
        benchExercise.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 10, weight: 135) }
        bench.exercises = [benchExercise]

        let supersetA = PlanBlockRecord(order: 1, kind: .superset, label: "Superset A", rounds: 3, restSeconds: 60)
        let inclineDB = PlanExerciseRecord(order: 0, name: "Incline DB Press", cue: "Squeeze at the top. Stop 1–2 reps short.")
        inclineDB.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 12, weight: 50) }
        let row = PlanExerciseRecord(order: 1, name: "Barbell Row", cue: "Flat back. Drive elbows to hips.")
        row.sets = (0..<3).map { PlanSetRecord(order: $0, reps: 10, weight: 135) }
        supersetA.exercises = [inclineDB, row]

        let circuit = PlanBlockRecord(order: 2, kind: .circuit, label: "Circuit", rounds: 3, restSeconds: 45)
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
