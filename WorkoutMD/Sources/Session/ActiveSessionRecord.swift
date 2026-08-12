import Foundation
import SwiftData

/// Durable single-record mirror of the live `WorkoutSession` (`docs/architecture/domain-primitives
/// .md` §8) — written the moment a workout starts (not just at Done) and kept current via
/// `ActiveSessionStore.save`, so a crash or forced-quit mid-workout can be resumed on next launch
/// instead of silently losing logged sets. `stateJSON` is an encoded `SessionState`: plan-
/// independent, so a resumed session doesn't depend on the originating `PlanRecord` still existing
/// or being unchanged. At most one `status == "inProgress"` row exists at a time — see
/// `ActiveSessionStore`.
@Model
final class ActiveSessionRecord {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var updatedAt: Date
    /// The originating `PlanRecord.id`, if any — mirrors `SessionState.activePlanID`, duplicated
    /// here (rather than only inside `stateJSON`) so it's queryable/inspectable without decoding.
    var planID: UUID?
    /// "inProgress" | "finished" | "discarded" — a plain `String` (not an enum), matching this
    /// schema's existing `RecordGroupKind`/`RecordCoachKind` convention of storing SwiftData-facing
    /// enums as raw strings.
    var status: String
    var stateJSON: String

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        updatedAt: Date = .now,
        planID: UUID? = nil,
        status: String = "inProgress",
        stateJSON: String
    ) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.planID = planID
        self.status = status
        self.stateJSON = stateJSON
    }
}
