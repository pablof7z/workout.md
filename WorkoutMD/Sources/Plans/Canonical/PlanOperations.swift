import Foundation

// MARK: - Composable plan operations
//
// See `docs/architecture/domain-primitives.md` §2. Structured operations over stable identifiers —
// creating a plan is applying a `PlanMutation` (an ordered batch of `PlanOp`s) to an empty
// `PlanSnapshot`. Every plan-changing outcome (create, import, collaborative build, edit a future
// workout, replace an exercise, restore a revision) is expressed as one of these; there are no
// special-purpose tool families. `PlanEngine.swift` is what actually applies them.

/// Three-state edit for one field of an `updateX`/`setPlanMeta` op: leave it alone, clear it to
/// `nil`, or set it to a new value. The wire representation is decided by the *containing* `PlanOp`,
/// not by `FieldEdit` itself — see the "CRITICAL JSON CONTRACT" note on `PlanOp` below. `FieldEdit`
/// still conforms to `Codable` (compiler-synthesized) so it can be used/tested standalone, but no op
/// in this file ever calls that synthesized `encode(to:)`/`init(from:)` directly.
enum FieldEdit<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    /// No change — the field's current value is left as-is.
    case keep
    /// Set the field to a new value.
    case set(T)
    /// Set the field to `nil` (only meaningful for optional targets, e.g. `restSeconds`).
    case clear
}

/// One structured plan edit, addressed by stable `UUID`s. `add*` ops carry a caller-supplied id so a
/// coach turn can add a block and then add exercises into it within a single atomic
/// `PlanMutation` — see `PlanEngine.apply`.
///
/// ## CRITICAL JSON CONTRACT
/// `PlanOp` implements `Codable` by hand (not compiler-synthesized) to produce a flat, LLM- and
/// Rust-tool-friendly wire shape:
/// - Every op encodes as a single flat JSON object with a `"op"` discriminator key whose value is
///   the case name verbatim (`"addBlock"`, `"updateSet"`, ...); the op's own fields are sibling keys
///   in that same object — e.g. `{"op":"addBlock","sessionID":"…","block":{…},"index":2}`.
/// - `FieldEdit` fields use **key presence** to distinguish the three states: key **absent** ⇒
///   `.keep`; key **present and `null`** ⇒ `.clear`; key **present with a value** ⇒ `.set(value)`.
///   This is implemented with `decodeIfPresent`-style `contains(_:)` checks in `decodeFieldEdit`
///   below, driven by this type's `init(from:)` — `FieldEdit` never encodes/decodes itself.
/// - `UUID`s that are direct fields of an op (`id`, `sessionID`, `blockID`, `exerciseID`,
///   `toSessionID`, `toBlockID`, `toExerciseID`) are encoded as **lowercased** strings (see
///   `encodeUUID`/`decodeUUID`). `UUID`s nested inside a payload value (`BlockSnapshot`,
///   `ExerciseSnapshot`, `SetSnapshot` — e.g. `addBlock`'s `block.id`) use `PlanSnapshot`'s ordinary
///   synthesized `Codable`, i.e. Foundation's standard (uppercase) `UUID` string form; only the op's
///   own addressing fields are normalized to lowercase.
/// - Optional `index: Int?` (and other plain optionals like `toSessionID`/`sets`) omit their key
///   entirely when `nil` — append-at-end / "don't move across containers" / "leave sets alone"
///   semantics, respectively — via `encodeIfPresent`/`decodeIfPresent`, not the absent-vs-null
///   `FieldEdit` convention (there is no third "explicitly clear" state for these).
enum PlanOp: Equatable, Sendable {
    case setPlanMeta(name: FieldEdit<String>, goal: FieldEdit<String>, notes: FieldEdit<String>)

    case addSession(id: UUID, name: String, index: Int?)
    case updateSession(id: UUID, name: FieldEdit<String>)
    case removeSession(id: UUID)
    case moveSession(id: UUID, toIndex: Int)
    case setCursor(sessionID: UUID?)

    case addBlock(sessionID: UUID, block: BlockSnapshot, index: Int?)
    case updateBlock(
        id: UUID, kind: FieldEdit<BlockKindSnapshot>, label: FieldEdit<String>,
        rounds: FieldEdit<Int>, restSeconds: FieldEdit<Int>
    )
    case removeBlock(id: UUID)
    case moveBlock(id: UUID, toSessionID: UUID?, toIndex: Int)

    case addExercise(blockID: UUID, exercise: ExerciseSnapshot, index: Int?)
    case updateExercise(id: UUID, name: FieldEdit<String>, cue: FieldEdit<String>)
    case replaceExercise(id: UUID, name: String, cue: FieldEdit<String>, sets: [SetSnapshot]?)
    case removeExercise(id: UUID)
    case moveExercise(id: UUID, toBlockID: UUID?, toIndex: Int)

    case addSet(exerciseID: UUID, set: SetSnapshot, index: Int?)
    case updateSet(
        id: UUID,
        reps: FieldEdit<Int>,
        weight: FieldEdit<Double>,
        seconds: FieldEdit<Int>,
        targetMinKg: FieldEdit<Double>,
        targetMaxKg: FieldEdit<Double>
    )
    case removeSet(id: UUID)
    case moveSet(id: UUID, toExerciseID: UUID?, toIndex: Int)
}

/// An atomic, ordered batch of `PlanOp`s — see `PlanEngine.apply`: either every op in the batch
/// succeeds, or none of it is committed.
struct PlanMutation: Codable, Equatable, Sendable {
    var operations: [PlanOp]
    /// Human-readable summary; auto-derived via `PlanEngine.summarize` when `nil`.
    var summary: String?
}

// MARK: - PlanOp Codable

extension PlanOp: Codable {
    private enum Op: String, Codable {
        case setPlanMeta
        case addSession, updateSession, removeSession, moveSession, setCursor
        case addBlock, updateBlock, removeBlock, moveBlock
        case addExercise, updateExercise, replaceExercise, removeExercise, moveExercise
        case addSet, updateSet, removeSet, moveSet
    }

    private enum CodingKeys: String, CodingKey {
        case op
        case id, sessionID, name, index, goal, notes
        case block, kind, label, rounds, restSeconds, toSessionID, toIndex
        case blockID, exercise, cue, toBlockID
        case sets
        case exerciseID, set, reps, weight, seconds, targetMinKg, targetMaxKg, toExerciseID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(Op.self, forKey: .op)
        switch op {
        case .setPlanMeta:
            self = .setPlanMeta(
                name: try decodeFieldEdit(String.self, forKey: .name, from: container),
                goal: try decodeFieldEdit(String.self, forKey: .goal, from: container),
                notes: try decodeFieldEdit(String.self, forKey: .notes, from: container)
            )

        case .addSession:
            self = .addSession(
                id: try decodeUUID(forKey: .id, from: container),
                name: try container.decode(String.self, forKey: .name),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        case .updateSession:
            self = .updateSession(
                id: try decodeUUID(forKey: .id, from: container),
                name: try decodeFieldEdit(String.self, forKey: .name, from: container)
            )
        case .removeSession:
            self = .removeSession(id: try decodeUUID(forKey: .id, from: container))
        case .moveSession:
            self = .moveSession(
                id: try decodeUUID(forKey: .id, from: container),
                toIndex: try container.decode(Int.self, forKey: .toIndex)
            )
        case .setCursor:
            self = .setCursor(sessionID: try decodeUUIDIfPresent(forKey: .sessionID, from: container))

        case .addBlock:
            self = .addBlock(
                sessionID: try decodeUUID(forKey: .sessionID, from: container),
                block: try container.decode(BlockSnapshot.self, forKey: .block),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        case .updateBlock:
            self = .updateBlock(
                id: try decodeUUID(forKey: .id, from: container),
                kind: try decodeFieldEdit(BlockKindSnapshot.self, forKey: .kind, from: container),
                label: try decodeFieldEdit(String.self, forKey: .label, from: container),
                rounds: try decodeFieldEdit(Int.self, forKey: .rounds, from: container),
                restSeconds: try decodeFieldEdit(Int.self, forKey: .restSeconds, from: container)
            )
        case .removeBlock:
            self = .removeBlock(id: try decodeUUID(forKey: .id, from: container))
        case .moveBlock:
            self = .moveBlock(
                id: try decodeUUID(forKey: .id, from: container),
                toSessionID: try decodeUUIDIfPresent(forKey: .toSessionID, from: container),
                toIndex: try container.decode(Int.self, forKey: .toIndex)
            )

        case .addExercise:
            self = .addExercise(
                blockID: try decodeUUID(forKey: .blockID, from: container),
                exercise: try container.decode(ExerciseSnapshot.self, forKey: .exercise),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        case .updateExercise:
            self = .updateExercise(
                id: try decodeUUID(forKey: .id, from: container),
                name: try decodeFieldEdit(String.self, forKey: .name, from: container),
                cue: try decodeFieldEdit(String.self, forKey: .cue, from: container)
            )
        case .replaceExercise:
            self = .replaceExercise(
                id: try decodeUUID(forKey: .id, from: container),
                name: try container.decode(String.self, forKey: .name),
                cue: try decodeFieldEdit(String.self, forKey: .cue, from: container),
                sets: try container.decodeIfPresent([SetSnapshot].self, forKey: .sets)
            )
        case .removeExercise:
            self = .removeExercise(id: try decodeUUID(forKey: .id, from: container))
        case .moveExercise:
            self = .moveExercise(
                id: try decodeUUID(forKey: .id, from: container),
                toBlockID: try decodeUUIDIfPresent(forKey: .toBlockID, from: container),
                toIndex: try container.decode(Int.self, forKey: .toIndex)
            )

        case .addSet:
            self = .addSet(
                exerciseID: try decodeUUID(forKey: .exerciseID, from: container),
                set: try container.decode(SetSnapshot.self, forKey: .set),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        case .updateSet:
            self = .updateSet(
                id: try decodeUUID(forKey: .id, from: container),
                reps: try decodeFieldEdit(Int.self, forKey: .reps, from: container),
                weight: try decodeFieldEdit(Double.self, forKey: .weight, from: container),
                seconds: try decodeFieldEdit(Int.self, forKey: .seconds, from: container),
                targetMinKg: try decodeFieldEdit(Double.self, forKey: .targetMinKg, from: container),
                targetMaxKg: try decodeFieldEdit(Double.self, forKey: .targetMaxKg, from: container)
            )
        case .removeSet:
            self = .removeSet(id: try decodeUUID(forKey: .id, from: container))
        case .moveSet:
            self = .moveSet(
                id: try decodeUUID(forKey: .id, from: container),
                toExerciseID: try decodeUUIDIfPresent(forKey: .toExerciseID, from: container),
                toIndex: try container.decode(Int.self, forKey: .toIndex)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .setPlanMeta(name, goal, notes):
            try container.encode(Op.setPlanMeta, forKey: .op)
            try encodeFieldEdit(name, forKey: .name, into: &container)
            try encodeFieldEdit(goal, forKey: .goal, into: &container)
            try encodeFieldEdit(notes, forKey: .notes, into: &container)

        case let .addSession(id, name, index):
            try container.encode(Op.addSession, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(index, forKey: .index)
        case let .updateSession(id, name):
            try container.encode(Op.updateSession, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try encodeFieldEdit(name, forKey: .name, into: &container)
        case let .removeSession(id):
            try container.encode(Op.removeSession, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
        case let .moveSession(id, toIndex):
            try container.encode(Op.moveSession, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try container.encode(toIndex, forKey: .toIndex)
        case let .setCursor(sessionID):
            try container.encode(Op.setCursor, forKey: .op)
            try encodeUUIDIfPresent(sessionID, forKey: .sessionID, into: &container)

        case let .addBlock(sessionID, block, index):
            try container.encode(Op.addBlock, forKey: .op)
            try encodeUUID(sessionID, forKey: .sessionID, into: &container)
            try container.encode(block, forKey: .block)
            try container.encodeIfPresent(index, forKey: .index)
        case let .updateBlock(id, kind, label, rounds, restSeconds):
            try container.encode(Op.updateBlock, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try encodeFieldEdit(kind, forKey: .kind, into: &container)
            try encodeFieldEdit(label, forKey: .label, into: &container)
            try encodeFieldEdit(rounds, forKey: .rounds, into: &container)
            try encodeFieldEdit(restSeconds, forKey: .restSeconds, into: &container)
        case let .removeBlock(id):
            try container.encode(Op.removeBlock, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
        case let .moveBlock(id, toSessionID, toIndex):
            try container.encode(Op.moveBlock, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try encodeUUIDIfPresent(toSessionID, forKey: .toSessionID, into: &container)
            try container.encode(toIndex, forKey: .toIndex)

        case let .addExercise(blockID, exercise, index):
            try container.encode(Op.addExercise, forKey: .op)
            try encodeUUID(blockID, forKey: .blockID, into: &container)
            try container.encode(exercise, forKey: .exercise)
            try container.encodeIfPresent(index, forKey: .index)
        case let .updateExercise(id, name, cue):
            try container.encode(Op.updateExercise, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try encodeFieldEdit(name, forKey: .name, into: &container)
            try encodeFieldEdit(cue, forKey: .cue, into: &container)
        case let .replaceExercise(id, name, cue, sets):
            try container.encode(Op.replaceExercise, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try container.encode(name, forKey: .name)
            try encodeFieldEdit(cue, forKey: .cue, into: &container)
            try container.encodeIfPresent(sets, forKey: .sets)
        case let .removeExercise(id):
            try container.encode(Op.removeExercise, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
        case let .moveExercise(id, toBlockID, toIndex):
            try container.encode(Op.moveExercise, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try encodeUUIDIfPresent(toBlockID, forKey: .toBlockID, into: &container)
            try container.encode(toIndex, forKey: .toIndex)

        case let .addSet(exerciseID, set, index):
            try container.encode(Op.addSet, forKey: .op)
            try encodeUUID(exerciseID, forKey: .exerciseID, into: &container)
            try container.encode(set, forKey: .set)
            try container.encodeIfPresent(index, forKey: .index)
        case let .updateSet(id, reps, weight, seconds, targetMinKg, targetMaxKg):
            try container.encode(Op.updateSet, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try encodeFieldEdit(reps, forKey: .reps, into: &container)
            try encodeFieldEdit(weight, forKey: .weight, into: &container)
            try encodeFieldEdit(seconds, forKey: .seconds, into: &container)
            try encodeFieldEdit(targetMinKg, forKey: .targetMinKg, into: &container)
            try encodeFieldEdit(targetMaxKg, forKey: .targetMaxKg, into: &container)
        case let .removeSet(id):
            try container.encode(Op.removeSet, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
        case let .moveSet(id, toExerciseID, toIndex):
            try container.encode(Op.moveSet, forKey: .op)
            try encodeUUID(id, forKey: .id, into: &container)
            try encodeUUIDIfPresent(toExerciseID, forKey: .toExerciseID, into: &container)
            try container.encode(toIndex, forKey: .toIndex)
        }
    }
}

// MARK: - Shared FieldEdit / UUID coding helpers

/// Encodes a `FieldEdit` per the key-presence contract documented on `PlanOp`: `.keep` omits `key`
/// entirely, `.clear` writes `null`, `.set(value)` writes `value`.
private func encodeFieldEdit<T: Codable, Key: CodingKey>(
    _ edit: FieldEdit<T>, forKey key: Key, into container: inout KeyedEncodingContainer<Key>
) throws {
    switch edit {
    case .keep:
        return
    case .clear:
        try container.encodeNil(forKey: key)
    case let .set(value):
        try container.encode(value, forKey: key)
    }
}

/// Decodes a `FieldEdit` per the key-presence contract documented on `PlanOp`: `key` absent ⇒
/// `.keep`, present-and-`null` ⇒ `.clear`, present-with-a-value ⇒ `.set(value)`.
private func decodeFieldEdit<T: Codable, Key: CodingKey>(
    _ type: T.Type, forKey key: Key, from container: KeyedDecodingContainer<Key>
) throws -> FieldEdit<T> {
    guard container.contains(key) else { return .keep }
    if try container.decodeNil(forKey: key) { return .clear }
    return .set(try container.decode(T.self, forKey: key))
}

/// Encodes a `UUID` as a lowercased string — the wire form for an op's own addressing fields (`id`,
/// `sessionID`, `blockID`, ...), per the contract documented on `PlanOp`.
private func encodeUUID<Key: CodingKey>(
    _ id: UUID, forKey key: Key, into container: inout KeyedEncodingContainer<Key>
) throws {
    try container.encode(id.uuidString.lowercased(), forKey: key)
}

private func decodeUUID<Key: CodingKey>(
    forKey key: Key, from container: KeyedDecodingContainer<Key>
) throws -> UUID {
    let raw = try container.decode(String.self, forKey: key)
    guard let uuid = UUID(uuidString: raw) else {
        throw DecodingError.dataCorruptedError(
            forKey: key, in: container, debugDescription: "Invalid UUID string: \(raw)")
    }
    return uuid
}

/// Optional-`UUID` counterpart of `encodeUUID`: omits `key` entirely when `id` is `nil` (append /
/// "stay in the same container" semantics — see the contract documented on `PlanOp`).
private func encodeUUIDIfPresent<Key: CodingKey>(
    _ id: UUID?, forKey key: Key, into container: inout KeyedEncodingContainer<Key>
) throws {
    guard let id else { return }
    try container.encode(id.uuidString.lowercased(), forKey: key)
}

private func decodeUUIDIfPresent<Key: CodingKey>(
    forKey key: Key, from container: KeyedDecodingContainer<Key>
) throws -> UUID? {
    guard let raw = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
    guard let uuid = UUID(uuidString: raw) else {
        throw DecodingError.dataCorruptedError(
            forKey: key, in: container, debugDescription: "Invalid UUID string: \(raw)")
    }
    return uuid
}
