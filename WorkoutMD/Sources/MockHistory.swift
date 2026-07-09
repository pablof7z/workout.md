import Foundation
import SwiftData

/// Seeds a couple of clearly-mock past sessions so History has something to show on first run,
/// without ever touching a live `WorkoutSession`. Runs once — if any `WorkoutRecord` already exists
/// (real or mock), this is a no-op, so it never overwrites genuine history.
enum MockHistory {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutRecord>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }

        context.insert(upperBodySession())
        context.insert(legDaySession())
        try? context.save()
    }

    private static func daysAgo(_ n: Int, hour: Int, minute: Int) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: -n, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private static func upperBodySession() -> WorkoutRecord {
        let record = WorkoutRecord(
            date: daysAgo(2, hour: 18, minute: 30),
            name: "Upper Body A",
            goal: "Hypertrophy",
            totalSets: 6,
            loggedSets: 6,
            averageRPE: 7.7,
            isMock: true
        )

        let bench = ExerciseRecord(order: 0, name: "Bench Press", blockName: "Bench Press", groupKind: .straight)
        bench.sets = [
            SetRecord(order: 0, setNumber: 1, prescribedReps: 10, prescribedWeight: 135, actualReps: 10, actualWeight: 135, rpe: 7),
            SetRecord(order: 1, setNumber: 2, prescribedReps: 10, prescribedWeight: 135, actualReps: 10, actualWeight: 135, rpe: 7.5),
            SetRecord(order: 2, setNumber: 3, prescribedReps: 10, prescribedWeight: 135, actualReps: 8, actualWeight: 135, rpe: 9)
        ]

        let superset = ExerciseRecord(order: 1, name: "Incline DB Press", blockName: "Superset A", groupKind: .superset, groupLabel: "Superset A")
        superset.sets = [
            SetRecord(order: 0, setNumber: 1, round: 1, totalRounds: 3, prescribedReps: 12, prescribedWeight: 50, actualReps: 12, actualWeight: 50, rpe: 7),
            SetRecord(order: 1, setNumber: 1, round: 2, totalRounds: 3, prescribedReps: 12, prescribedWeight: 50, actualReps: 12, actualWeight: 50, rpe: 7.5),
            SetRecord(order: 2, setNumber: 1, round: 3, totalRounds: 3, prescribedReps: 12, prescribedWeight: 50, actualReps: 10, actualWeight: 50, rpe: 8)
        ]

        record.exercises = [bench, superset]
        record.coachNotes = [
            CoachNoteRecord(order: 0, kind: .coach, text: "On Bench Press. Tell me how it feels.", exerciseName: "Bench Press"),
            CoachNoteRecord(order: 1, kind: .user, text: "Getting heavy on the last set", exerciseName: "Bench Press"),
            CoachNoteRecord(order: 2, kind: .coach, text: "Noted.", exerciseName: "Bench Press")
        ]
        return record
    }

    private static func legDaySession() -> WorkoutRecord {
        let record = WorkoutRecord(
            date: daysAgo(6, hour: 7, minute: 15),
            name: "Lower Body B",
            goal: "Strength",
            totalSets: 6,
            loggedSets: 5,
            averageRPE: 8.4,
            isMock: true
        )

        let skippedSet = SetRecord(order: 2, setNumber: 3, prescribedReps: 5, prescribedWeight: 185)
        skippedSet.skipped = true

        let squat = ExerciseRecord(order: 0, name: "Back Squat", blockName: "Back Squat", groupKind: .straight)
        squat.sets = [
            SetRecord(order: 0, setNumber: 1, prescribedReps: 5, prescribedWeight: 185, actualReps: 5, actualWeight: 185, rpe: 8),
            SetRecord(order: 1, setNumber: 2, prescribedReps: 5, prescribedWeight: 185, actualReps: 5, actualWeight: 185, rpe: 8.5),
            skippedSet
        ]

        let legPress = ExerciseRecord(order: 1, name: "Leg Press", blockName: "Leg Press", groupKind: .straight)
        legPress.sets = [
            SetRecord(order: 0, setNumber: 1, prescribedReps: 12, prescribedWeight: 270, actualReps: 12, actualWeight: 270, rpe: 8),
            SetRecord(order: 1, setNumber: 2, prescribedReps: 12, prescribedWeight: 270, actualReps: 12, actualWeight: 270, rpe: 8.5),
            SetRecord(order: 2, setNumber: 3, prescribedReps: 12, prescribedWeight: 270, actualReps: 10, actualWeight: 270, rpe: 9)
        ]

        record.exercises = [squat, legPress]
        record.coachNotes = [
            CoachNoteRecord(order: 0, kind: .coach, text: "On Back Squat. Tell me how it feels.", exerciseName: "Back Squat"),
            CoachNoteRecord(order: 1, kind: .user, text: "Knee felt a bit off on set 3", exerciseName: "Back Squat"),
            CoachNoteRecord(order: 2, kind: .coach, text: "Sharp or dull? Cut your next set to 50%.", exerciseName: "Back Squat"),
            CoachNoteRecord(order: 3, kind: .diff, text: "Next Back Squat: 185 → 90 lb", exerciseName: "Back Squat")
        ]
        return record
    }
}
