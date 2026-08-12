import Foundation
import SwiftData

// MARK: - Persisted plan schema
//
// `PlanRecord` is the editable, durable source of truth for a workout template — what `TodayView`
// shows and starts, what the runner/`WorkoutSession` is built from, and what the coach's
// `plan_apply` tool (via `AppCoachHost.planApply` -> `PlanRepository`) mutates. Exactly one
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
    /// The cursor session id — "what's next" (see `PlanSnapshot.cursorSessionID` /
    /// domain-primitives.md §1). `nil` means "the first ordered session". Added NULLABLE so existing
    /// stores lightweight-migrate for free; `PlanMigrator.backfill` fills it in for legacy plans.
    var nextSessionID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \PlanBlockRecord.plan)
    var blocks: [PlanBlockRecord] = []

    /// Additive, sits *alongside* the untouched `blocks` relationship rather than reparenting it —
    /// see the migration-safety note on `PlanSessionRecord`. A plan's blocks are still owned via
    /// `blocks`/`PlanBlockRecord.plan`; sessions merely group them via `PlanBlockRecord.sessionID`.
    @Relationship(deleteRule: .cascade, inverse: \PlanSessionRecord.plan)
    var sessions: [PlanSessionRecord] = []

    init(
        id: UUID = UUID(),
        name: String,
        goal: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        isActive: Bool = false,
        nextSessionID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.notes = notes
        self.createdAt = createdAt
        self.isActive = isActive
        self.nextSessionID = nextSessionID
    }

    var orderedSessions: [PlanSessionRecord] { sessions.sorted { $0.order < $1.order } }

    /// The session `nextSessionID` resolves to, or the first ordered session if the cursor is `nil`/
    /// stale — mirrors `PlanSnapshot.nextSession`'s "no calendar" resolution (domain-primitives.md
    /// §1).
    var resolvedSession: PlanSessionRecord? {
        if let nextSessionID, let match = sessions.first(where: { $0.id == nextSessionID }) {
            return match
        }
        return orderedSessions.first
    }

    /// `session`'s blocks, in order — blocks are matched by `PlanBlockRecord.sessionID`, not by a
    /// SwiftData relationship (see the migration-safety note on `PlanSessionRecord`).
    func blocks(in session: PlanSessionRecord) -> [PlanBlockRecord] {
        blocks.filter { $0.sessionID == session.id }.sorted { $0.order < $1.order }
    }

    /// The blocks the runner/Today should actually run: the resolved session's blocks. Falls back to
    /// every block whose `sessionID` is still `nil` when no session exists yet, so a not-yet-backfilled
    /// (or brand-new, pre-`PlanMigrator`) plan still renders — for a migrated single-session plan this
    /// equals the full block list, i.e. no behavior change for existing single-session plans.
    var orderedBlocks: [PlanBlockRecord] {
        if let resolvedSession {
            return blocks(in: resolvedSession)
        }
        return blocks.filter { $0.sessionID == nil }.sorted { $0.order < $1.order }
    }

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
    /// Which `PlanSessionRecord` this block belongs to. NULLABLE and added additively so existing
    /// stores lightweight-migrate for free (see the migration-safety note on `PlanSessionRecord`);
    /// `nil` means "not yet grouped into a session" — `PlanMigrator.backfill` stamps every legacy
    /// block once. The `plan` relationship below is intentionally left untouched (still how a block
    /// is owned/cascade-deleted); `sessionID` only *groups* blocks that already belong to `plan`.
    var sessionID: UUID?

    var plan: PlanRecord?

    @Relationship(deleteRule: .cascade, inverse: \PlanExerciseRecord.block)
    var exercises: [PlanExerciseRecord] = []

    init(
        id: UUID = UUID(),
        order: Int,
        kind: PlanBlockKind,
        label: String,
        rounds: Int = 1,
        restSeconds: Int? = nil,
        sessionID: UUID? = nil
    ) {
        self.id = id
        self.order = order
        self.kind = kind
        self.label = label
        self.rounds = rounds
        self.restSeconds = restSeconds
        self.sessionID = sessionID
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

/// One prescribed set: reps/weight, a plain timed hold, or a Tindeq-measured timed hold. The two
/// optional kilogram bounds are additive columns so existing stores lightweight-migrate safely.
@Model
final class PlanSetRecord {
    var id: UUID
    /// Position within the exercise (== round index for a group exercise), for stable ordering.
    var order: Int
    var reps: Int?
    var weight: Double?
    var seconds: Int?
    var targetMinKg: Double?
    var targetMaxKg: Double?

    var exercise: PlanExerciseRecord?

    init(
        id: UUID = UUID(), order: Int, reps: Int? = nil, weight: Double? = nil,
        seconds: Int? = nil, targetMinKg: Double? = nil, targetMaxKg: Double? = nil
    ) {
        self.id = id
        self.order = order
        self.reps = reps
        self.weight = weight
        self.seconds = seconds
        self.targetMinKg = targetMinKg
        self.targetMaxKg = targetMaxKg
    }

    var asSetTarget: SetTarget {
        if let seconds, let targetMinKg, let targetMaxKg {
            return .tindeq(
                seconds: seconds,
                targetMinKg: min(targetMinKg, targetMaxKg),
                targetMaxKg: max(targetMinKg, targetMaxKg)
            )
        }
        if let seconds { return .timed(seconds: seconds) }
        return .reps(count: reps ?? 0, weight: weight)
    }

    var displayString: String { asSetTarget.displayString }
}

// MARK: - Sessions (multi-session plans)
//
// See `docs/architecture/domain-primitives.md` §1/§4/§12. `PlanSessionRecord` sits ADDITIVELY
// alongside the existing `plan -> PlanBlockRecord` shape rather than reparenting `PlanBlockRecord`
// onto it: a structural relationship move is a SwiftData custom-migration minefield against real
// user stores, whereas a brand-new model plus nullable columns
// (`PlanRecord.nextSessionID`/`PlanBlockRecord.sessionID`) are both changes SwiftData's automatic
// lightweight migration handles for free — no `SchemaMigrationPlan` needed. `PlanMigrator.backfill`
// is the idempotent code-side step that groups any pre-existing (nil-`sessionID`) blocks into one
// synthesized session so every plan ends up with `sessions.count >= 1`.

/// One workout within a plan — "Upper A", "Lower B", ... — mirrors `SessionSnapshot`. Blocks are
/// associated by `PlanBlockRecord.sessionID`, not by a SwiftData relationship — see the note above.
@Model
final class PlanSessionRecord {
    @Attribute(.unique) var id: UUID
    /// Position within the plan's session list, for stable ordering.
    var order: Int
    var name: String

    var plan: PlanRecord?

    init(id: UUID = UUID(), order: Int, name: String) {
        self.id = id
        self.order = order
        self.name = name
    }
}

/// One stored snapshot of a plan at a point in time — the durable history behind restore. Mirrors
/// `docs/architecture/domain-primitives.md` §4: `snapshotJSON` is the full `PlanSnapshot` that
/// resulted from applying `mutationJSON` (the `PlanMutation` that produced it, `nil` for a baseline/
/// imported revision with no originating mutation).
@Model
final class PlanRevisionRecord {
    @Attribute(.unique) var id: UUID
    /// The `PlanRecord.id` this revision belongs to — not a SwiftData relationship, since a revision
    /// must remain a durable, independent historical record even if the plan itself is later deleted.
    var planID: UUID
    var createdAt: Date
    var summary: String
    var snapshotJSON: String
    var mutationJSON: String?

    init(
        id: UUID = UUID(),
        planID: UUID,
        createdAt: Date = .now,
        summary: String,
        snapshotJSON: String,
        mutationJSON: String? = nil
    ) {
        self.id = id
        self.planID = planID
        self.createdAt = createdAt
        self.summary = summary
        self.snapshotJSON = snapshotJSON
        self.mutationJSON = mutationJSON
    }
}
