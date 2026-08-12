import Foundation
import SwiftData

// MARK: - ActiveSessionStore
//
// See `docs/architecture/domain-primitives.md` §8. The single write/read gateway over
// `ActiveSessionRecord` — mirrors `PlanRepository`/`MemoryStore`'s shape: a lightweight
// namespace-ish type over an explicit `ModelContext` the caller already has in scope, not a
// singleton or an `@Observable` service. At most one `status == "inProgress"` record exists at a
// time; `save` always upserts that one record rather than ever inserting a second.
struct ActiveSessionStore {
    let context: ModelContext

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Write

    /// Upserts the single `inProgress` record with a fresh `SessionState` snapshot of `session`.
    /// Called on session start (the first durable representation exists before any set is logged —
    /// `RootView.startSession`) and on every subsequent mutation, debounced via
    /// `WorkoutSession.onChange` (`RootView`'s `scheduleSave`). A no-op if `session` fails to encode
    /// (should not happen in practice — `SessionState` is a plain value type).
    func save(_ session: WorkoutSession) {
        guard let data = try? Self.encoder.encode(SessionState.from(session)),
              let json = String(data: data, encoding: .utf8) else { return }

        if let existing = currentInProgress() {
            existing.stateJSON = json
            existing.updatedAt = .now
            existing.planID = session.activePlan?.id
        } else {
            let record = ActiveSessionRecord(
                startedAt: session.startedAt, planID: session.activePlan?.id, stateJSON: json
            )
            context.insert(record)
        }
        try? context.save()
    }

    /// Marks the current `inProgress` record `finished` — called once the corresponding
    /// `WorkoutRecord` has been saved (`RootView.saveToHistory`), so the resume prompt never
    /// reappears for a workout that was actually completed normally.
    func markFinished() {
        guard let record = currentInProgress() else { return }
        record.status = "finished"
        try? context.save()
    }

    /// Deletes the current `inProgress` record outright — once the athlete has explicitly chosen not
    /// to resume, there's nothing worth keeping around under a "discarded" status.
    func discard() {
        guard let record = currentInProgress() else { return }
        context.delete(record)
        try? context.save()
    }

    // MARK: - Read

    func currentInProgress() -> ActiveSessionRecord? {
        var descriptor = FetchDescriptor<ActiveSessionRecord>(predicate: #Predicate { $0.status == "inProgress" })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Decodes the current `inProgress` record's `stateJSON` and rebuilds a live `WorkoutSession`
    /// from it via `WorkoutSession.restore(from:modelContext:)` — `nil` if there is none, or if it
    /// fails to decode (a corrupt/incompatible row is treated the same as "nothing to resume" rather
    /// than crashing launch).
    func loadSession(modelContext: ModelContext) -> WorkoutSession? {
        guard let record = currentInProgress(),
              let state = try? Self.decoder.decode(SessionState.self, from: Data(record.stateJSON.utf8))
        else { return nil }
        return WorkoutSession.restore(from: state, modelContext: modelContext)
    }
}
