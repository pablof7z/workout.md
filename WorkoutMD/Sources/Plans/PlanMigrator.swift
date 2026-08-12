import Foundation
import SwiftData

// MARK: - Legacy-plan session backfill
//
// See `docs/architecture/domain-primitives.md` §12. `PlanSessionRecord`/`PlanBlockRecord.sessionID`
// were added ADDITIVELY (new model + nullable column — see the migration-safety note on
// `PlanSessionRecord` in PlanModels.swift) so SwiftData's automatic lightweight migration handles the
// store with no `SchemaMigrationPlan`. What lightweight migration can't do is GROUP a pre-existing
// plan's blocks into a session — that's this idempotent code-side step, run once at launch (see
// `WorkoutMDApp.swift`).
enum PlanMigrator {
    private static let encoder = JSONEncoder()

    /// For every `PlanRecord` with zero sessions: creates one `PlanSessionRecord(order: 0, name:
    /// "Workout")`, attaches it, points `plan.nextSessionID` at it, stamps every one of that plan's
    /// blocks with its id, and — if the plan has no revisions yet — writes a baseline
    /// `PlanRevisionRecord` ("Imported existing plan") capturing the now-sessioned snapshot. A plan
    /// that already has at least one session is left untouched, which is what makes a second call a
    /// no-op: nothing here reads or writes `WorkoutRecord`/history at all.
    static func backfill(context: ModelContext) {
        let descriptor = FetchDescriptor<PlanRecord>()
        guard let plans = try? context.fetch(descriptor) else { return }

        var didChange = false
        for plan in plans where plan.sessions.isEmpty {
            let session = PlanSessionRecord(order: 0, name: "Workout")
            context.insert(session)
            session.plan = plan
            plan.sessions.append(session)
            plan.nextSessionID = session.id

            for block in plan.blocks {
                block.sessionID = session.id
            }
            didChange = true

            if hasNoRevisions(planID: plan.id, context: context) {
                writeBaselineRevision(for: plan, context: context)
            }
        }

        guard didChange else { return }
        try? context.save()
    }

    private static func hasNoRevisions(planID: UUID, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<PlanRevisionRecord>(
            predicate: #Predicate { $0.planID == planID }
        )
        return ((try? context.fetchCount(descriptor)) ?? 0) == 0
    }

    private static func writeBaselineRevision(for plan: PlanRecord, context: ModelContext) {
        let snapshot = plan.toSnapshot()
        guard let snapshotData = try? encoder.encode(snapshot) else { return }
        let revision = PlanRevisionRecord(
            planID: plan.id,
            summary: "Imported existing plan",
            snapshotJSON: String(decoding: snapshotData, as: UTF8.self),
            mutationJSON: nil
        )
        context.insert(revision)
    }
}
