import Foundation
import SwiftData

// MARK: - General durable memory schema
//
// See `docs/architecture/domain-primitives.md` §5. A `MemoryRecord` is a FREEFORM,
// coaching-relevant fact or note about the athlete — "prefers morning sessions", "recovering
// from a shoulder tweak", "dislikes Bulgarian split squats" — not a structured field for any
// particular category. There are deliberately no per-category tools or mandatory schema fields
// for equipment/goals/schedule/injuries/preferences/etc.: one general primitive family covers
// all of them, the same way `PlanOp` covers every plan-changing outcome instead of five narrow
// tools. `tags` is freeform too (the coach/athlete choose whatever words are useful — "goal",
// "injury", "schedule", ...); nothing in this file enumerates or validates them.
//
// Deliberately distinct from: the coach transcript (`CoachNoteRecord` — what was *said*, turn by
// turn), uploaded reference docs (`DoctrineStore` — training doctrine the athlete supplies),
// the current plan + its revisions (`PlanRecord`/`PlanRevisionRecord` — what's *prescribed*),
// the live in-progress workout, and completed history (`WorkoutRecord` — what actually
// happened). A memory is the durable, athlete-scoped fact layer that outlives all of those.

/// One durable, freeform note about the athlete that the coach should keep in mind across turns
/// and app launches — e.g. a goal, a schedule preference, a dislike, an injury note, or anything
/// else worth remembering that doesn't fit a more specific record type.
@Model
final class MemoryRecord {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// Bumped on every edit (see `MemoryStore.update`); memory surfaces — `digest()` and the
    /// Settings management list — sort by this so the most recently touched facts lead.
    var updatedAt: Date
    var text: String
    /// Freeform labels, e.g. `["goal"]` or `["dislike"]` — no fixed vocabulary; see the file-level
    /// doc comment above.
    var tags: [String]
    /// Where this memory came from: `"coach"` (added by the coach mid-conversation), `"onboarding"`
    /// (captured during onboarding), or `"user"` (added directly by the athlete in the Coach Memory
    /// settings screen).
    var source: String

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        text: String,
        tags: [String] = [],
        source: String = "coach"
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.text = text
        self.tags = tags
        self.source = source
    }
}
