import Foundation

// MARK: - Canonical plan value model
//
// See `docs/architecture/domain-primitives.md` §1. `PlanSnapshot` is the single canonical,
// `Codable`/`Equatable`/`Sendable` value form of a workout plan — used by `PlanOp`/`PlanEngine`
// mutations, revision storage (as JSON), unapplied proposals, the Markdown round-trip, and the
// coach wire format. It intentionally does NOT know about SwiftData: `PlanRecord`/`PlanBlockRecord`/
// `PlanExerciseRecord`/`PlanSetRecord` (see `PlanModels.swift`) are the *persisted* graph a
// `PlanRepository` reconciles to/from a snapshot — reconciliation is a later slice.
//
// Ordering is array order (not a stored `order: Int`, unlike the SwiftData records). Every element
// carries a stable `UUID` that survives edits, moves, and reconciliation.

/// The canonical representation of an entire workout plan: an ordered list of future sessions plus
/// a cursor identifying "what's next" (see `nextSession` below).
struct PlanSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var goal: String?
    var notes: String?
    /// Ordered; a plan expresses one or more future workouts (a single-session plan is just
    /// `sessions.count == 1`).
    var sessions: [SessionSnapshot]
    /// The session "what's next" resolves to. `nil` means "the first session" — see `nextSession`.
    var cursorSessionID: UUID?
}

/// One workout within the plan — "Upper A", "Lower B", etc. — as an ordered list of blocks.
struct SessionSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var blocks: [BlockSnapshot]
}

/// A group of exercises performed together: straight sets (one exercise), a superset, or a circuit.
struct BlockSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var kind: BlockKindSnapshot
    var label: String
    /// Rounds for a superset/circuit; conventionally unused (1) for straight sets, where the
    /// exercise's own `sets` count is what matters.
    var rounds: Int
    /// Rest between rounds, seconds — group blocks only.
    var restSeconds: Int?
    var exercises: [ExerciseSnapshot]
}

/// How a `BlockSnapshot` is organized. Mirrors `PlanBlockKind` (see `PlanModels.swift`) in the
/// SwiftData layer, kept as a separate type so the value layer has zero SwiftData coupling.
enum BlockKindSnapshot: String, Codable, Sendable {
    case straight
    case superset
    case circuit
}

/// One movement within a block: a name, the coach's cue, and its ordered prescribed sets.
struct ExerciseSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var cue: String
    var sets: [SetSnapshot]
}

/// One prescribed set. A non-nil `seconds` value is timed; when both kilogram bounds are also
/// present, it is a Tindeq-measured hold.
struct SetSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var reps: Int?
    var weight: Double?
    var seconds: Int?
    var targetMinKg: Double? = nil
    var targetMaxKg: Double? = nil
}

// MARK: - Lookups by id

extension PlanSnapshot {
    /// The session at `cursorSessionID`, or the first session if the cursor is `nil` or no longer
    /// resolves to any session in `sessions` (e.g. a stale cursor after an out-of-band edit). This is
    /// the "no calendar" next-workout resolution described in domain-primitives.md §1: completing a
    /// session advances the cursor to the next session (round-robin); repair moves the cursor or
    /// edits the upcoming session directly.
    var nextSession: SessionSnapshot? {
        if let cursorSessionID, let match = findSession(cursorSessionID) {
            return match
        }
        return sessions.first
    }

    func findSession(_ id: UUID) -> SessionSnapshot? {
        sessions.first { $0.id == id }
    }

    /// The block with `id`, together with the id of the session containing it.
    func findBlock(_ id: UUID) -> (block: BlockSnapshot, sessionID: UUID)? {
        for session in sessions {
            if let block = session.blocks.first(where: { $0.id == id }) {
                return (block, session.id)
            }
        }
        return nil
    }

    /// The exercise with `id`, together with the id of the block containing it.
    func findExercise(_ id: UUID) -> (exercise: ExerciseSnapshot, blockID: UUID)? {
        for session in sessions {
            for block in session.blocks {
                if let exercise = block.exercises.first(where: { $0.id == id }) {
                    return (exercise, block.id)
                }
            }
        }
        return nil
    }

    /// The set with `id`, together with the id of the exercise containing it.
    func findSet(_ id: UUID) -> (set: SetSnapshot, exerciseID: UUID)? {
        for session in sessions {
            for block in session.blocks {
                for exercise in block.exercises {
                    if let set = exercise.sets.first(where: { $0.id == id }) {
                        return (set, exercise.id)
                    }
                }
            }
        }
        return nil
    }
}
