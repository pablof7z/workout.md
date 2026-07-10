import Foundation
import SwiftData

// MARK: - Persisted plan schema
//
// `PlanRecord` is the editable, durable source of truth for a workout template — what `TodayView`
// shows and starts, what the runner/`WorkoutSession` is built from, and what the coach's
// `edit_plan` tool (see `WorkoutSession.applyEditPlan` in `Models.swift`) mutates. Exactly one
// `PlanRecord` is `isActive` at a time (enforced by `PlanStore.setActive`).
//
// Shape: `PlanRecord` -> ordered `PlanBlockRecord` (straight sets / superset / circuit) -> ordered
// `PlanExerciseRecord` (name + coach cue) -> ordered `PlanSetRecord` (prescribed reps/weight or a
// timed hold). See `PlanConversion.swift` for how this graph becomes the `[WorkoutBlock]`/
// `[WorkoutStep]` shapes `Models.swift` already knows how to run and render.

/// How a `PlanBlockRecord` is organized. Mirrors `GroupKind` plus a "straight sets" case, stored as
/// a plain `String` (via `RawRepresentable`) the same way `RecordGroupKind` is in
/// `PersistenceModels.swift`.
enum PlanBlockKind: String, Codable, CaseIterable, Identifiable {
    case straight
    case superset
    case circuit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .straight: return "Straight Sets"
        case .superset: return "Superset"
        case .circuit: return "Circuit"
        }
    }

    var groupKind: GroupKind? {
        switch self {
        case .straight: return nil
        case .superset: return .superset
        case .circuit: return .circuit
        }
    }
}

@Model
final class PlanRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var goal: String?
    var notes: String?
    var createdAt: Date
    var isActive: Bool

    @Relationship(deleteRule: .cascade, inverse: \PlanBlockRecord.plan)
    var blocks: [PlanBlockRecord] = []

    init(
        id: UUID = UUID(),
        name: String,
        goal: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.notes = notes
        self.createdAt = createdAt
        self.isActive = isActive
    }

    var orderedBlocks: [PlanBlockRecord] { blocks.sorted { $0.order < $1.order } }

    var allExercises: [PlanExerciseRecord] { orderedBlocks.flatMap { $0.orderedExercises } }

    /// Total prescribed sets across every block — one straight-sets exercise's sets, or (rounds ×
    /// exercise count) for a group — used for the estimate below and any future volume math.
    var totalSetCount: Int {
        orderedBlocks.reduce(0) { total, block in
            let exercises = block.orderedExercises
            switch block.kind {
            case .straight:
                return total + (exercises.first?.sets.count ?? 0)
            case .superset, .circuit:
                let rounds = exercises.map(\.sets.count).max() ?? block.rounds
                return total + rounds * exercises.count
            }
        }
    }

    /// Rough, deliberately approximate session length — not a hardcoded label like the old
    /// prototype's static "~45 min", but a live estimate that changes as the plan is edited.
    var estimatedMinutes: Int {
        max(10, Int((Double(totalSetCount) * 2.2).rounded()))
    }

    /// "3 blocks · ~40 min · Hypertrophy" — shown on Today and in the Plans list.
    var summary: String {
        var parts = ["\(blocks.count) block\(blocks.count == 1 ? "" : "s")"]
        parts.append("~\(estimatedMinutes) min")
        if let goal, !goal.isEmpty { parts.append(goal) }
        return parts.joined(separator: " · ")
    }
}

@Model
final class PlanBlockRecord {
    var id: UUID
    /// Position within the plan, for stable ordering (SwiftData relationship arrays are unordered).
    var order: Int
    var kind: PlanBlockKind
    var label: String
    /// Rounds for a superset/circuit; unused (fixed at 1) for straight sets, where the exercise's
    /// own `sets` count is what matters.
    var rounds: Int
    /// Rest between rounds, seconds — group blocks only.
    var restSeconds: Int?

    var plan: PlanRecord?

    @Relationship(deleteRule: .cascade, inverse: \PlanExerciseRecord.block)
    var exercises: [PlanExerciseRecord] = []

    init(
        id: UUID = UUID(),
        order: Int,
        kind: PlanBlockKind,
        label: String,
        rounds: Int = 1,
        restSeconds: Int? = nil
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.label = label
        self.rounds = rounds
        self.restSeconds = restSeconds
    }

    var orderedExercises: [PlanExerciseRecord] { exercises.sorted { $0.order < $1.order } }
}

@Model
final class PlanExerciseRecord {
    var id: UUID
    /// Position within the block, for stable ordering.
    var order: Int
    var name: String
    /// The coach's cue for this movement — shown on the runner's set page.
    var cue: String

    var block: PlanBlockRecord?

    @Relationship(deleteRule: .cascade, inverse: \PlanSetRecord.exercise)
    var sets: [PlanSetRecord] = []

    init(id: UUID = UUID(), order: Int, name: String, cue: String = "") {
        self.id = id
        self.order = order
        self.name = name
        self.cue = cue
    }

    var orderedSets: [PlanSetRecord] { sets.sorted { $0.order < $1.order } }
}

/// One prescribed set: either a rep/weight target or a timed hold (mirrors `SetTarget` — `seconds`
/// set means timed, otherwise reps/weight apply). For a superset/circuit exercise, each entry here
/// corresponds to one round.
@Model
final class PlanSetRecord {
    var id: UUID
    /// Position within the exercise (== round index for a group exercise), for stable ordering.
    var order: Int
    var reps: Int?
    var weight: Double?
    var seconds: Int?

    var exercise: PlanExerciseRecord?

    init(id: UUID = UUID(), order: Int, reps: Int? = nil, weight: Double? = nil, seconds: Int? = nil) {
        self.id = id
        self.order = order
        self.reps = reps
        self.weight = weight
        self.seconds = seconds
    }

    var asSetTarget: SetTarget {
        if let seconds { return .timed(seconds: seconds) }
        return .reps(count: reps ?? 0, weight: weight)
    }

    var displayString: String { asSetTarget.displayString }
}
