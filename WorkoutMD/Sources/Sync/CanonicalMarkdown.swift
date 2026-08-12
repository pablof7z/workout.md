import Foundation

// MARK: - Canonical (hidden, machine-restorable) Markdown block
//
// See `docs/architecture/domain-primitives.md` §11. `MarkdownGenerator` renders the pretty, HUMAN
// body of a session/plan — that stays exactly as it is today. This file adds a second, RESTORABLE
// representation appended to the same file, wrapped in an HTML comment so it never shows up in any
// rendered/previewed Markdown:
//
//     <!-- workout.md:canonical v1
//     { ...compact JSON... }
//     -->
//
// `plan.md` and `sessions/*.md` are the two canonical, restorable artifacts — `MarkdownParser`
// extracts and decodes this block to reconstruct SwiftData records (`CanonicalImporter`) on a fresh
// install / second device. `README.md` is explicitly EXPORT-ONLY (a human-readable index of session
// files) and never carries a canonical block — it is never a restore source, only ever generated,
// never parsed. Every canonical-Markdown call site in this codebase should honor that split.

/// The `SessionDTO`-side canonical value type: a lossless, `Codable` mirror of a `WorkoutRecord`
/// graph (id, date, name, goal, totals, every exercise's every set — prescribed *and* actual — and
/// the coach transcript), so a completed session round-trips through Markdown without losing any
/// logged fact. `PlanSnapshot` (`Plans/Canonical/PlanSnapshot.swift`) already plays this role for
/// plans; this is its session-history counterpart.
struct SessionDTO: Codable, Equatable {
    var id: UUID
    var planID: UUID? = nil
    var date: Date
    var name: String
    var goal: String?
    var totalSets: Int
    var loggedSets: Int
    var averageRPE: Double?
    var isMock: Bool
    var exercises: [ExerciseDTO]
    var coachNotes: [CoachNoteDTO]

    struct ExerciseDTO: Codable, Equatable {
        var id: UUID
        var order: Int
        var name: String
        var blockName: String
        var groupKind: RecordGroupKind
        var groupLabel: String?
        var sets: [SetDTO]
    }

    struct SetDTO: Codable, Equatable {
        var id: UUID
        var order: Int
        var setNumber: Int
        var round: Int?
        var totalRounds: Int?
        var prescribedReps: Int?
        var prescribedWeight: Double?
        var prescribedSeconds: Int?
        var prescribedTargetMinKg: Double? = nil
        var prescribedTargetMaxKg: Double? = nil
        var actualReps: Int?
        var actualWeight: Double?
        var actualSeconds: Int?
        var actualPeakKg: Double? = nil
        var actualAverageKg: Double? = nil
        var actualTimeInTargetSeconds: Double? = nil
        var rpe: Double?
        var skipped: Bool
        var substituted: Bool
        var substitutedName: String?
        var notes: String?
        var sourceStepID: UUID?
    }

    struct CoachNoteDTO: Codable, Equatable {
        var id: UUID
        var order: Int
        var kind: RecordCoachKind
        var text: String
        var exerciseName: String?
        var date: Date
        var planID: UUID?
    }
}

// MARK: - WorkoutRecord <-> SessionDTO

extension SessionDTO {
    /// Snapshots a persisted `WorkoutRecord` graph into its canonical value form. Pure/read-only —
    /// does not touch `record` or its `ModelContext`.
    static func from(_ record: WorkoutRecord) -> SessionDTO {
        SessionDTO(
            id: record.id,
            planID: record.planID,
            date: record.date,
            name: record.name,
            goal: record.goal,
            totalSets: record.totalSets,
            loggedSets: record.loggedSets,
            averageRPE: record.averageRPE,
            isMock: record.isMock,
            exercises: record.exercises.sorted { $0.order < $1.order }.map { exercise in
                ExerciseDTO(
                    id: exercise.id,
                    order: exercise.order,
                    name: exercise.name,
                    blockName: exercise.blockName,
                    groupKind: exercise.groupKind,
                    groupLabel: exercise.groupLabel,
                    sets: exercise.sets.sorted { $0.order < $1.order }.map { set in
                        SetDTO(
                            id: set.id,
                            order: set.order,
                            setNumber: set.setNumber,
                            round: set.round,
                            totalRounds: set.totalRounds,
                            prescribedReps: set.prescribedReps,
                            prescribedWeight: set.prescribedWeight,
                            prescribedSeconds: set.prescribedSeconds,
                            prescribedTargetMinKg: set.prescribedTargetMinKg,
                            prescribedTargetMaxKg: set.prescribedTargetMaxKg,
                            actualReps: set.actualReps,
                            actualWeight: set.actualWeight,
                            actualSeconds: set.actualSeconds,
                            actualPeakKg: set.actualPeakKg,
                            actualAverageKg: set.actualAverageKg,
                            actualTimeInTargetSeconds: set.actualTimeInTargetSeconds,
                            rpe: set.rpe,
                            skipped: set.skipped,
                            substituted: set.substituted,
                            substitutedName: set.substitutedName,
                            notes: set.notes,
                            sourceStepID: set.sourceStepID
                        )
                    }
                )
            },
            coachNotes: record.coachNotes.sorted { $0.order < $1.order }.map { note in
                CoachNoteDTO(
                    id: note.id,
                    order: note.order,
                    kind: note.kind,
                    text: note.text,
                    exerciseName: note.exerciseName,
                    date: note.date,
                    planID: note.planID
                )
            }
        )
    }

    /// Reconstructs a full, unsaved `WorkoutRecord` graph (exercises, sets, coach notes) from this
    /// DTO. Mirrors `WorkoutSession.makeRecord`'s shape but is a pure value->graph materialization —
    /// the caller (`CanonicalImporter`) decides whether/how to insert it into a `ModelContext`.
    func makeRecord() -> WorkoutRecord {
        let record = WorkoutRecord(
            id: id, planID: planID, date: date, name: name, goal: goal,
            totalSets: totalSets, loggedSets: loggedSets, averageRPE: averageRPE, isMock: isMock
        )
        record.exercises = exercises.map { exerciseDTO in
            let exerciseRecord = ExerciseRecord(
                id: exerciseDTO.id, order: exerciseDTO.order, name: exerciseDTO.name,
                blockName: exerciseDTO.blockName, groupKind: exerciseDTO.groupKind,
                groupLabel: exerciseDTO.groupLabel
            )
            exerciseRecord.sets = exerciseDTO.sets.map { setDTO in
                SetRecord(
                    id: setDTO.id, order: setDTO.order, setNumber: setDTO.setNumber,
                    round: setDTO.round, totalRounds: setDTO.totalRounds,
                    prescribedReps: setDTO.prescribedReps, prescribedWeight: setDTO.prescribedWeight,
                    prescribedSeconds: setDTO.prescribedSeconds,
                    prescribedTargetMinKg: setDTO.prescribedTargetMinKg,
                    prescribedTargetMaxKg: setDTO.prescribedTargetMaxKg,
                    actualReps: setDTO.actualReps, actualWeight: setDTO.actualWeight,
                    actualSeconds: setDTO.actualSeconds,
                    actualPeakKg: setDTO.actualPeakKg,
                    actualAverageKg: setDTO.actualAverageKg,
                    actualTimeInTargetSeconds: setDTO.actualTimeInTargetSeconds,
                    rpe: setDTO.rpe, skipped: setDTO.skipped, substituted: setDTO.substituted,
                    substitutedName: setDTO.substitutedName, notes: setDTO.notes,
                    sourceStepID: setDTO.sourceStepID
                )
            }
            return exerciseRecord
        }
        record.coachNotes = coachNotes.map { noteDTO in
            CoachNoteRecord(
                id: noteDTO.id, order: noteDTO.order, kind: noteDTO.kind, text: noteDTO.text,
                exerciseName: noteDTO.exerciseName, date: noteDTO.date, planID: noteDTO.planID
            )
        }
        return record
    }
}

// MARK: - Hidden comment block encoding

enum CanonicalMarkdown {
    static let marker = "workout.md:canonical"
    static let version = "v1"

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Encodes `value` and wraps it as `<!-- workout.md:canonical v1\n{json}\n-->` — an HTML
    /// comment, so it renders as nothing in any Markdown viewer/preview, while staying trivially
    /// findable/parseable by `MarkdownParser.canonicalJSON(in:)`. Returns an empty string if `value`
    /// somehow fails to encode (never expected for these DTOs — all-`Codable`, no custom
    /// encode(to:) — but this stays a soft failure rather than a crash on a sync/export path).
    static func block(for value: some Encodable) -> String {
        guard let data = try? encoder.encode(value), let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return "<!-- \(marker) \(version)\n\(json)\n-->"
    }
}
