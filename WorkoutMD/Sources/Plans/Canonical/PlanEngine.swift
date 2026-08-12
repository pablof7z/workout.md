import Foundation

// MARK: - Pure plan mutation engine
//
// See `docs/architecture/domain-primitives.md` §2. `PlanEngine` is a pure function over
// `PlanSnapshot` values — no SwiftData, no I/O, no singletons — so it's trivially unit-testable
// (`PlanEngineTests.swift`) and safe to run identically for creating a plan, editing a future
// session, or replaying a stored `PlanRevisionRecord.mutationJSON` during restore.

enum PlanEngineError: Error, Equatable {
    /// A `PlanOp` referenced a `UUID` (session/block/exercise/set, or a `move*` destination
    /// container) that doesn't exist in the snapshot.
    case unknownID(UUID)
    /// An explicit `index`/`toIndex` was negative or greater than the destination array's count.
    /// `index == count` (append at the end) is valid and does NOT throw this.
    case indexOutOfRange
    /// A `move*` op's source and destination were structurally incompatible (reserved for future
    /// use; the current op set has no such case, since every `move*` destination is validated the
    /// same way as an `add*` destination).
    case invalidMove
    /// `setPlanMeta` tried to clear the plan `name` or set it to an empty/whitespace-only string —
    /// `name` is the plan's required identity, unlike `goal`/`notes`.
    case emptyPlanName
}

enum PlanEngine {

    /// A brand-new, empty plan: no sessions, no cursor. Mutations (`addSession`, `addBlock`, ...)
    /// build it up from here — "create a plan" IS "apply a `PlanMutation` to `PlanEngine.empty`".
    static func empty(id: UUID = UUID(), name: String) -> PlanSnapshot {
        PlanSnapshot(id: id, name: name, goal: nil, notes: nil, sessions: [], cursorSessionID: nil)
    }

    /// Applies every op in `mutation` in order to a copy of `snapshot` and returns the result.
    /// ATOMIC: ops are applied to a local `var` working copy; the moment any op throws, this
    /// function throws too and returns nothing — since `PlanSnapshot` is a value type and `snapshot`
    /// is an immutable parameter, the caller's original snapshot was never touched, so "nothing is
    /// committed" falls out of Swift's value semantics rather than needing an explicit rollback.
    static func apply(_ mutation: PlanMutation, to snapshot: PlanSnapshot) throws -> PlanSnapshot {
        var working = snapshot
        for op in mutation.operations {
            try apply(op, to: &working)
        }
        return working
    }

    // MARK: - Per-op application

    private static func apply(_ op: PlanOp, to snapshot: inout PlanSnapshot) throws {
        switch op {
        case let .setPlanMeta(name, goal, notes):
            try applyPlanName(name, to: &snapshot.name)
            applyOptionalField(goal, to: &snapshot.goal)
            applyOptionalField(notes, to: &snapshot.notes)

        case let .addSession(id, name, index):
            let idx = try insertIndex(index, count: snapshot.sessions.count)
            snapshot.sessions.insert(SessionSnapshot(id: id, name: name, blocks: []), at: idx)

        case let .updateSession(id, name):
            guard let sIdx = snapshot.sessions.firstIndex(where: { $0.id == id }) else {
                throw PlanEngineError.unknownID(id)
            }
            applyRequiredField(name, to: &snapshot.sessions[sIdx].name)

        case let .removeSession(id):
            guard let sIdx = snapshot.sessions.firstIndex(where: { $0.id == id }) else {
                throw PlanEngineError.unknownID(id)
            }
            snapshot.sessions.remove(at: sIdx)
            // Cursor-removal policy (documented per the design's "clear or advance sensibly"
            // requirement): if the removed session held the cursor, advance to whatever session now
            // occupies that same index — i.e. the session that was "next after" the removed one in
            // round-robin order — clamped to the last session if the removed one was last, or clear
            // the cursor entirely if no sessions remain.
            if snapshot.cursorSessionID == id {
                if snapshot.sessions.isEmpty {
                    snapshot.cursorSessionID = nil
                } else {
                    snapshot.cursorSessionID = snapshot.sessions[min(sIdx, snapshot.sessions.count - 1)].id
                }
            }

        case let .moveSession(id, toIndex):
            guard let sIdx = snapshot.sessions.firstIndex(where: { $0.id == id }) else {
                throw PlanEngineError.unknownID(id)
            }
            let session = snapshot.sessions.remove(at: sIdx)
            let target = try validateIndex(toIndex, count: snapshot.sessions.count)
            snapshot.sessions.insert(session, at: target)

        case let .setCursor(sessionID):
            if let sessionID, snapshot.findSession(sessionID) == nil {
                throw PlanEngineError.unknownID(sessionID)
            }
            snapshot.cursorSessionID = sessionID

        case let .addBlock(sessionID, block, index):
            guard let sIdx = snapshot.sessions.firstIndex(where: { $0.id == sessionID }) else {
                throw PlanEngineError.unknownID(sessionID)
            }
            let idx = try insertIndex(index, count: snapshot.sessions[sIdx].blocks.count)
            snapshot.sessions[sIdx].blocks.insert(block, at: idx)

        case let .updateBlock(id, kind, label, rounds, restSeconds):
            guard let (sIdx, bIdx) = locateBlock(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            applyRequiredField(kind, to: &snapshot.sessions[sIdx].blocks[bIdx].kind)
            applyRequiredField(label, to: &snapshot.sessions[sIdx].blocks[bIdx].label)
            applyRequiredField(rounds, to: &snapshot.sessions[sIdx].blocks[bIdx].rounds)
            applyOptionalField(restSeconds, to: &snapshot.sessions[sIdx].blocks[bIdx].restSeconds)

        case let .removeBlock(id):
            guard let (sIdx, bIdx) = locateBlock(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            snapshot.sessions[sIdx].blocks.remove(at: bIdx)

        case let .moveBlock(id, toSessionID, toIndex):
            guard let (sIdx, bIdx) = locateBlock(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            let block = snapshot.sessions[sIdx].blocks.remove(at: bIdx)
            let destSIdx: Int
            if let toSessionID {
                guard let idx = snapshot.sessions.firstIndex(where: { $0.id == toSessionID }) else {
                    throw PlanEngineError.unknownID(toSessionID)
                }
                destSIdx = idx
            } else {
                destSIdx = sIdx
            }
            let target = try validateIndex(toIndex, count: snapshot.sessions[destSIdx].blocks.count)
            snapshot.sessions[destSIdx].blocks.insert(block, at: target)

        case let .addExercise(blockID, exercise, index):
            guard let (sIdx, bIdx) = locateBlock(blockID, in: snapshot) else {
                throw PlanEngineError.unknownID(blockID)
            }
            let idx = try insertIndex(index, count: snapshot.sessions[sIdx].blocks[bIdx].exercises.count)
            snapshot.sessions[sIdx].blocks[bIdx].exercises.insert(exercise, at: idx)

        case let .updateExercise(id, name, cue):
            guard let (sIdx, bIdx, eIdx) = locateExercise(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            applyRequiredField(name, to: &snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].name)
            applyRequiredField(cue, to: &snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].cue)

        case let .replaceExercise(id, name, cue, sets):
            guard let (sIdx, bIdx, eIdx) = locateExercise(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].name = name
            applyRequiredField(cue, to: &snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].cue)
            if let sets {
                snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets = sets
            }

        case let .removeExercise(id):
            guard let (sIdx, bIdx, eIdx) = locateExercise(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            snapshot.sessions[sIdx].blocks[bIdx].exercises.remove(at: eIdx)

        case let .moveExercise(id, toBlockID, toIndex):
            guard let (sIdx, bIdx, eIdx) = locateExercise(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            let exercise = snapshot.sessions[sIdx].blocks[bIdx].exercises.remove(at: eIdx)
            let dest: (session: Int, block: Int)
            if let toBlockID {
                guard let destLoc = locateBlock(toBlockID, in: snapshot) else {
                    throw PlanEngineError.unknownID(toBlockID)
                }
                dest = destLoc
            } else {
                dest = (sIdx, bIdx)
            }
            let target = try validateIndex(
                toIndex, count: snapshot.sessions[dest.session].blocks[dest.block].exercises.count)
            snapshot.sessions[dest.session].blocks[dest.block].exercises.insert(exercise, at: target)

        case let .addSet(exerciseID, set, index):
            guard let (sIdx, bIdx, eIdx) = locateExercise(exerciseID, in: snapshot) else {
                throw PlanEngineError.unknownID(exerciseID)
            }
            let idx = try insertIndex(
                index, count: snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets.count)
            snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets.insert(set, at: idx)

        case let .updateSet(id, reps, weight, seconds, targetMinKg, targetMaxKg):
            guard let (sIdx, bIdx, eIdx, setIdx) = locateSet(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            applyOptionalField(
                reps, to: &snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets[setIdx].reps)
            applyOptionalField(
                weight, to: &snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets[setIdx].weight)
            applyOptionalField(
                seconds, to: &snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets[setIdx].seconds)
            applyOptionalField(
                targetMinKg,
                to: &snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets[setIdx].targetMinKg)
            applyOptionalField(
                targetMaxKg,
                to: &snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets[setIdx].targetMaxKg)

        case let .removeSet(id):
            guard let (sIdx, bIdx, eIdx, setIdx) = locateSet(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets.remove(at: setIdx)

        case let .moveSet(id, toExerciseID, toIndex):
            guard let (sIdx, bIdx, eIdx, setIdx) = locateSet(id, in: snapshot) else {
                throw PlanEngineError.unknownID(id)
            }
            let set = snapshot.sessions[sIdx].blocks[bIdx].exercises[eIdx].sets.remove(at: setIdx)
            let dest: (session: Int, block: Int, exercise: Int)
            if let toExerciseID {
                guard let destLoc = locateExercise(toExerciseID, in: snapshot) else {
                    throw PlanEngineError.unknownID(toExerciseID)
                }
                dest = destLoc
            } else {
                dest = (sIdx, bIdx, eIdx)
            }
            let target = try validateIndex(
                toIndex, count: snapshot.sessions[dest.session].blocks[dest.block].exercises[dest.exercise].sets.count)
            snapshot.sessions[dest.session].blocks[dest.block].exercises[dest.exercise].sets
                .insert(set, at: target)
        }
    }

    // MARK: - Lookup helpers (index paths, not just the element, since we mutate in place)

    private static func locateBlock(_ id: UUID, in snapshot: PlanSnapshot) -> (session: Int, block: Int)? {
        for (sIdx, session) in snapshot.sessions.enumerated() {
            if let bIdx = session.blocks.firstIndex(where: { $0.id == id }) {
                return (sIdx, bIdx)
            }
        }
        return nil
    }

    private static func locateExercise(
        _ id: UUID, in snapshot: PlanSnapshot
    ) -> (session: Int, block: Int, exercise: Int)? {
        for (sIdx, session) in snapshot.sessions.enumerated() {
            for (bIdx, block) in session.blocks.enumerated() {
                if let eIdx = block.exercises.firstIndex(where: { $0.id == id }) {
                    return (sIdx, bIdx, eIdx)
                }
            }
        }
        return nil
    }

    private static func locateSet(
        _ id: UUID, in snapshot: PlanSnapshot
    ) -> (session: Int, block: Int, exercise: Int, set: Int)? {
        for (sIdx, session) in snapshot.sessions.enumerated() {
            for (bIdx, block) in session.blocks.enumerated() {
                for (eIdx, exercise) in block.exercises.enumerated() {
                    if let setIdx = exercise.sets.firstIndex(where: { $0.id == id }) {
                        return (sIdx, bIdx, eIdx, setIdx)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Index validation

    /// Resolves an optional insertion index: `nil` ⇒ append at the end. `index == count` is a valid
    /// append-at-end and does not throw; anything else out of `0...count` throws `indexOutOfRange`.
    private static func insertIndex(_ index: Int?, count: Int) throws -> Int {
        guard let index else { return count }
        return try validateIndex(index, count: count)
    }

    private static func validateIndex(_ index: Int, count: Int) throws -> Int {
        guard index >= 0, index <= count else { throw PlanEngineError.indexOutOfRange }
        return index
    }

    // MARK: - FieldEdit application

    /// Applies a `FieldEdit` to an *optional* target: `.keep` leaves it, `.clear` sets it to `nil`,
    /// `.set(v)` sets it to `v`.
    private static func applyOptionalField<T>(_ edit: FieldEdit<T>, to target: inout T?) {
        switch edit {
        case .keep: return
        case .clear: target = nil
        case let .set(value): target = value
        }
    }

    /// Applies a `FieldEdit` to a *required* (non-optional) target. `.clear` has no representable
    /// value to fall back to for a required field, so it's treated as a no-op (same as `.keep`)
    /// rather than an error — callers that mean "reset this" should `.set` an explicit value.
    private static func applyRequiredField<T>(_ edit: FieldEdit<T>, to target: inout T) {
        switch edit {
        case .keep, .clear: return
        case let .set(value): target = value
        }
    }

    /// `setPlanMeta`'s `name` is the one required-`String` field with an explicit validation error:
    /// the plan's name may never be cleared or set to empty/whitespace-only text.
    private static func applyPlanName(_ edit: FieldEdit<String>, to target: inout String) throws {
        switch edit {
        case .keep:
            return
        case .clear:
            throw PlanEngineError.emptyPlanName
        case let .set(value):
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PlanEngineError.emptyPlanName
            }
            target = value
        }
    }

    // MARK: - Human summary

    /// A terse, human-readable summary of `mutation`, used to fill `PlanMutation.summary` when the
    /// caller didn't supply one (e.g. `"Added Bench Press; removed 1 set"`). Counts operations of the
    /// same kind together; when there's exactly one `add`/`replace` of a session/block/exercise, the
    /// name is shown instead of a bare count.
    static func summarize(_ mutation: PlanMutation) -> String {
        guard !mutation.operations.isEmpty else { return "No changes" }

        var order: [String] = []
        var counts: [String: Int] = [:]
        var lastName: [String: String] = [:]

        func tally(_ key: String, name: String? = nil) {
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
            if let name { lastName[key] = name }
        }

        for op in mutation.operations {
            switch op {
            case .setPlanMeta: tally("setPlanMeta")
            case let .addSession(_, name, _): tally("addSession", name: name)
            case .updateSession: tally("updateSession")
            case .removeSession: tally("removeSession")
            case .moveSession: tally("moveSession")
            case .setCursor: tally("setCursor")
            case let .addBlock(_, block, _): tally("addBlock", name: block.label)
            case .updateBlock: tally("updateBlock")
            case .removeBlock: tally("removeBlock")
            case .moveBlock: tally("moveBlock")
            case let .addExercise(_, exercise, _): tally("addExercise", name: exercise.name)
            case .updateExercise: tally("updateExercise")
            case let .replaceExercise(_, name, _, _): tally("replaceExercise", name: name)
            case .removeExercise: tally("removeExercise")
            case .moveExercise: tally("moveExercise")
            case .addSet: tally("addSet")
            case .updateSet: tally("updateSet")
            case .removeSet: tally("removeSet")
            case .moveSet: tally("moveSet")
            }
        }

        let clauses: [String] = order.map { key in
            let count = counts[key] ?? 1
            let name = lastName[key]
            return Self.clause(for: key, count: count, name: name)
        }

        var summary = clauses.joined(separator: "; ")
        if let first = summary.first {
            summary.replaceSubrange(summary.startIndex...summary.startIndex, with: String(first).uppercased())
        }
        return summary
    }

    private static func clause(for key: String, count: Int, name: String?) -> String {
        func plural(_ noun: String) -> String { count == 1 ? noun : "\(noun)s" }

        switch key {
        case "setPlanMeta": return "updated plan details"
        case "setCursor": return "changed next workout"

        case "addSession":
            if count == 1, let name { return "added session \"\(name)\"" }
            return "added \(count) \(plural("session"))"
        case "addBlock":
            if count == 1, let name { return "added \(name)" }
            return "added \(count) \(plural("block"))"
        case "addExercise":
            if count == 1, let name { return "added \(name)" }
            return "added \(count) \(plural("exercise"))"
        case "addSet":
            return "added \(count) \(plural("set"))"

        case "replaceExercise":
            if count == 1, let name { return "replaced exercise with \(name)" }
            return "replaced \(count) \(plural("exercise"))"

        case "removeSession": return "removed \(count) \(plural("session"))"
        case "removeBlock": return "removed \(count) \(plural("block"))"
        case "removeExercise": return "removed \(count) \(plural("exercise"))"
        case "removeSet": return "removed \(count) \(plural("set"))"

        case "updateSession": return count == 1 ? "renamed a session" : "updated \(count) sessions"
        case "updateBlock": return count == 1 ? "updated a block" : "updated \(count) blocks"
        case "updateExercise": return count == 1 ? "updated an exercise" : "updated \(count) exercises"
        case "updateSet": return count == 1 ? "updated a set" : "updated \(count) sets"

        case "moveSession": return "reordered sessions"
        case "moveBlock": return count == 1 ? "moved a block" : "moved \(count) blocks"
        case "moveExercise": return count == 1 ? "moved an exercise" : "moved \(count) exercises"
        case "moveSet": return count == 1 ? "reordered a set" : "reordered \(count) sets"

        default: return key
        }
    }
}
