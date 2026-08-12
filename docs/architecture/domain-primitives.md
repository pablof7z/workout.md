# Workout.md — Domain Primitives Architecture

Status: settled contract for the coach re-architecture. Every implementation slice
builds against this. Source-grounded against the existing codebase (July 2026).

This document defines the small set of composable domain primitives that replace the
prototype coach seams. It does **not** rebuild the working runner, SwiftData history,
Markdown rendering, provider config, or the Rust streaming coach — it replaces the
seams between them.

---

## 0. What stays, what changes

Retained as-is (do not rebuild):
- Native runner (`RunnerView`/`StepPageView`/`SessionView`/`ControlsView`) — already
  id-based per-set state.
- SwiftData history graph (`WorkoutRecord`/`ExerciseRecord`/`SetRecord`/`CoachNoteRecord`).
- `MarkdownGenerator` rendering (we ADD a parser beside it).
- Provider config / BYOK (`AppSettings`, `CoachSecrets`, `BYOKProviderConnector`).
- Rust `CoachEngine` UniFFI streaming architecture (`configure_coach` + `send_message`
  + `CoachSink`/`CoachHost` callbacks). We change the **tool set**, not the transport.
- Nostr/fabric module.

Replaced:
- `PlanEditInterpreter` (substring/prose matcher) → canonical `PlanEngine` + `PlanOp`s.
- 5 narrow Rust tools (`adjust_set`/`skip_set`/`deload_exercise`/`add_note`/`edit_plan`)
  → general primitives (`plan_apply`/`plan_get`/`plan_restore`/`memory_*`/`session_apply`).
- WorkoutSession-owned coach (`CoachController.send(...session:exerciseName:)`) →
  app-level `CoachService` with optional session context.
- 3-slide `OnboardingView` gate → coach conversation onboarding.
- Launch-time seed of "Upper Body A" → sample/fixture starter option only.
- `zip(prescribedSteps, steps)` positional snapshot → prescribed-travels-with-step.

Added:
- `PlanSnapshot` canonical value model + `PlanOp`/`PlanMutation` + `PlanEngine`.
- `PlanRevisionRecord` + restore. `PlanSessionRecord` (multi-session) + cursor.
- `MemoryRecord` + `MemoryStore` general memory primitives.
- `ActiveSessionRecord` durable in-progress session + resume/discard.
- `TranscriptionProvider` (Apple Speech default, ElevenLabs optional) + voice UI.
- Markdown parser + tested round-trip + sync restore + conflict policy.
- `VersionedSchema` V1→V2 migration.

---

## 1. Canonical plan model (value layer)

One representation. `PlanSnapshot` is a `Codable`, `Equatable`, identity-stable value
type. It is the single canonical form used by: mutations, revisions (stored as JSON),
proposals (unapplied candidate), Markdown round-trip, and the coach wire format.
Ordering is **array order** in the snapshot; SwiftData `order: Int` is derived on
reconcile. Every element carries a stable `UUID`.

```
struct PlanSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var goal: String?
    var notes: String?
    var sessions: [SessionSnapshot]   // ordered; a plan expresses ≥1 future workout
    var cursorSessionID: UUID?        // next workout to run; nil ⇒ first session
}
struct SessionSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var name: String                  // "Upper A", "Lower B", ...
    var blocks: [BlockSnapshot]
}
struct BlockSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var kind: BlockKindSnapshot        // .straight | .superset | .circuit
    var label: String
    var rounds: Int
    var restSeconds: Int?
    var exercises: [ExerciseSnapshot]
}
struct ExerciseSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var cue: String
    var sets: [SetSnapshot]
}
struct SetSnapshot: Codable, Equatable, Sendable {
    var id: UUID
    var reps: Int?
    var weight: Double?
    var seconds: Int?                  // timed if non-nil
}
enum BlockKindSnapshot: String, Codable, Sendable { case straight, superset, circuit }
```

### Next-workout resolution (no calendar)
The plan holds ordered `sessions` and a `cursorSessionID`. "What's next" = the session
at the cursor (or first if nil). Completing a session advances the cursor to the next
session (round-robin). Repair = the coach edits the upcoming session or moves the
cursor — never a rigid date/day-of-week. This is the smallest coherent model that
expresses more than one future workout. A single-session plan is just `sessions.count == 1`.

---

## 2. Composable operations (`PlanOp`) + atomic mutation

Structured operations over stable identifiers. Creating a plan is applying mutations to
an empty snapshot. Every plan-changing outcome — create, import, collaborative build,
edit a future workout, replace an exercise, restore — is expressed here. No
special-purpose tool families.

```
enum PlanOp: Codable, Equatable, Sendable {
    case setPlanMeta(name: FieldEdit<String>, goal: FieldEdit<String>, notes: FieldEdit<String>)

    case addSession(id: UUID, name: String, index: Int?)     // append if index nil
    case updateSession(id: UUID, name: FieldEdit<String>)
    case removeSession(id: UUID)
    case moveSession(id: UUID, toIndex: Int)
    case setCursor(sessionID: UUID?)

    case addBlock(sessionID: UUID, block: BlockSnapshot, index: Int?)
    case updateBlock(id: UUID, kind: FieldEdit<BlockKindSnapshot>, label: FieldEdit<String>,
                     rounds: FieldEdit<Int>, restSeconds: FieldEdit<Int>)
    case removeBlock(id: UUID)
    case moveBlock(id: UUID, toSessionID: UUID?, toIndex: Int)

    case addExercise(blockID: UUID, exercise: ExerciseSnapshot, index: Int?)
    case updateExercise(id: UUID, name: FieldEdit<String>, cue: FieldEdit<String>)
    case replaceExercise(id: UUID, name: String, cue: FieldEdit<String>, sets: [SetSnapshot]?)
    case removeExercise(id: UUID)
    case moveExercise(id: UUID, toBlockID: UUID?, toIndex: Int)

    case addSet(exerciseID: UUID, set: SetSnapshot, index: Int?)
    case updateSet(id: UUID, reps: FieldEdit<Int>, weight: FieldEdit<Double>, seconds: FieldEdit<Int>)
    case removeSet(id: UUID)
    case moveSet(id: UUID, toExerciseID: UUID?, toIndex: Int)
}

// Absent = leave unchanged; explicit clear = set to nil. Distinguishes the two.
enum FieldEdit<T: Codable & Equatable>: Codable, Equatable, Sendable {
    case keep          // no change
    case set(T)
    case clear         // set to nil (only meaningful for optional targets)
}

struct PlanMutation: Codable, Equatable, Sendable {
    var operations: [PlanOp]
    var summary: String?     // human-readable; auto-derived if nil
}
```

### PlanEngine — pure, atomic, testable
```
enum PlanEngine {
    static func empty(id: UUID, name: String) -> PlanSnapshot
    static func apply(_ mutation: PlanMutation, to snapshot: PlanSnapshot) throws -> PlanSnapshot
}
enum PlanEngineError: Error { case unknownID(UUID), indexOutOfRange, invalidMove, emptyPlanName }
```
`apply` works on a value copy. All ops apply in order; **any failure throws and nothing
is committed** (atomic). New ids in `add*` ops are caller-supplied so the coach can add a
block and then add exercises into it within one atomic batch. No SwiftData in `PlanEngine`
— it is a pure function, unit-tested exhaustively.

---

## 3. Apply-by-default, propose-when-iterating

```
enum PlanApplyMode { case apply, propose }
struct PlanApplyResult { let snapshot: PlanSnapshot; let revisionID: UUID?; let proposed: Bool }
```
- `.apply` (default): reconcile SwiftData graph to the new snapshot, write a
  `PlanRevisionRecord`, save. Coach-generated mutations use this by default.
- `.propose`: return the candidate snapshot only; DO NOT reconcile/persist. UI previews
  it and either confirms (re-applies in `.apply`) or discards. A proposal is the SAME
  mutation mechanism on the SAME model — not a separate pipeline.

Generated plans no longer wait for manual activation: creating a plan via the coach
applies and activates by default.

---

## 4. Persistence, revisions, restore (`PlanRepository`)

New SwiftData models (added to schema V2):
```
@Model PlanSessionRecord { id: UUID; order: Int; name: String;
    plan: PlanRecord?; blocks: [PlanBlockRecord] (cascade) }   // sits between plan & block
// PlanRecord gains: var nextSessionID: UUID?   (cursor)
// PlanBlockRecord.plan relationship → replaced by .session relationship

@Model PlanRevisionRecord {
    @Attribute(.unique) id: UUID; planID: UUID; createdAt: Date;
    summary: String; snapshotJSON: String; mutationJSON: String? }
```
`PlanRepository` (owns `ModelContext`):
- `snapshot(of planID:) -> PlanSnapshot?` / `activeSnapshot() -> PlanSnapshot?`
- `apply(_ mutation:, to planID:, mode:) throws -> PlanApplyResult`
- `createPlan(_ mutation:, activate: Bool) throws -> PlanSnapshot` (empty + apply)
- `revisions(of planID:) -> [PlanRevisionRecord]` (newest first)
- `restore(revisionID:) throws -> PlanApplyResult`  ← itself a normal versioned change:
   builds a "replace whole plan content" mutation from the revision snapshot, applies in
   `.apply` mode (creating a new revision).

**Reconcile** = upsert-by-UUID diff between the current SwiftData graph and the target
snapshot: update matched (preserving object identity so `@Query` views animate), insert
new, delete missing, set `order` from array index. No index/zip assumptions.

---

## 5. General durable memory (`MemoryStore`)

One freeform primitive family. No mandatory category fields for equipment/goals/injuries/etc.
```
@Model MemoryRecord {
    @Attribute(.unique) id: UUID; createdAt: Date; updatedAt: Date;
    text: String; tags: [String]; source: String }   // source: "coach"|"onboarding"|"migrated"|"user"
```
`MemoryStore` API: `add(text:tags:source:) -> UUID`, `update(id:text?:tags?:)`,
`remove(id:)`, `query(text?:tags?:limit?) -> [MemoryRecord]`, `digest(limit:) -> String`.
Query is substring + tag match + recency (no vector store in v1).

Distinct concepts kept separate (invariant 4): transcript (`CoachNoteRecord`), durable
memory (`MemoryRecord`), uploaded reference docs (`DoctrineStore` — unchanged), current
plan + revisions, active workout state (`ActiveSessionRecord`), completed history
(`WorkoutRecord`).

Migration folds existing `AppSettings.primaryGoal`/`sessionLengthMinutes`/
`dislikedExercises` into seed `MemoryRecord`s (`source: "migrated"`). After migration the
coach context reads memory as the source of truth; Settings goal fields remain as a
convenience editor that also writes the corresponding memory (no indefinite parallel truth).

---

## 6. App-level coach, session optional (`CoachService`)

The engine is already session-agnostic; coupling lives only in Swift's
`CoachController.send(...)`. Introduce `CoachService` owning a single `CoachEngine`,
callable with optional context:
```
enum CoachMode { case onboarding, planning, today, activeWorkout, exercise, historyReview }
struct CoachContext {
    var mode: CoachMode
    var memories: String            // MemoryStore.digest
    var planSnapshot: PlanSnapshot? // active plan (for stable ids)
    var recentHistory: [WorkoutRecord]
    var doctrine: String
    var session: SessionGrounding?  // present only when a workout is live
    var focusExercise: String?      // optional
}
```
`CoachService.converse(context:, userText:, sink:)` assembles the bounded context,
configures the engine per role, and drives the turn with a `CoachHost` that dispatches
the general tools to `PlanRepository` / `MemoryStore` / `ActiveSessionStore` — **not** to
a WorkoutSession. When a live session exists the host also handles `session_apply`.
WorkoutSession no longer owns coach state or tools; it exposes a `SessionGrounding`
snapshot and accepts `session_apply` results.

Every invocation (onboarding, planning, live) sees the current memory digest — whenever
memories change, the digest is recomputed for the next call.

---

## 7. New coach tool set (Rust `tools.rs` + Swift host)

All tools still route through `host.apply_tool(name, args_json) -> String`. Replace the
five narrow tools with general primitives:

| Tool | Purpose | Args |
|---|---|---|
| `plan_get` | Read current plan snapshot (stable ids to reference) | `{}` |
| `plan_apply` | Apply/propose an atomic batch of plan ops | `{ operations: [PlanOp-json], propose?: bool, summary?: string }` |
| `plan_revisions` | List restorable revisions | `{}` |
| `plan_restore` | Restore a revision (new versioned change) | `{ revision_id: string }` |
| `memory_add` | Record a durable memory | `{ text: string, tags?: [string] }` |
| `memory_update` | Edit a memory | `{ id: string, text?: string, tags?: [string] }` |
| `memory_query` | Recall memories | `{ query?: string, tags?: [string], limit?: int }` |
| `memory_remove` | Delete a memory | `{ id: string }` |
| `session_apply` | Mutate the LIVE workout (adjust/skip/substitute/add set) — only when a session is live | `{ operations: [SessionOp-json] }` |

`plan_apply` is the single plan-mutation tool. The coach composes create/import/edit/
replace/reorder through its `operations`. `session_apply` is a distinct domain (active
workout state), available only when a workout is live; it addresses sets by stable id.
Doctrine remains uploaded-reference material (optionally `doctrine_list`/`doctrine_get`
read-only).

The JSON op encoding mirrors the Swift `PlanOp`/`SessionOp` Codable forms exactly so a
single schema serves Rust tool declaration, the LLM, and the Swift decoder.

---

## 8. Durable active workout (`ActiveSessionStore`)

```
@Model ActiveSessionRecord {
    @Attribute(.unique) id: UUID; startedAt: Date; updatedAt: Date;
    planID: UUID?; planRevisionID: UUID?; status: String;   // "inProgress"|"finished"|"discarded"
    stateJSON: String }     // serialized SessionState: steps (id, prescribed, actual, state, rpe,
                            // substitution), cursor, session-local plan edits, transcript refs
```
Written on session start (first durable representation — not at Done), debounced on every
mutation (done/skip, reps/weight, coach `session_apply`), cleared/marked finished after
`WorkoutRecord` is saved. On launch, if an `inProgress` record exists → offer Resume or
Discard. Resume rebuilds `WorkoutSession` from `stateJSON`.

### Stable identity in prescribed-vs-actual
Each `WorkoutStep` already has a stable `.id`. Attach the frozen `prescribed` values
**and** the originating `SetSnapshot.id` to each step's info; `SetPageInfo` carries both
`prescribed` (immutable) and `actual` (mutable). `makeRecord` iterates `steps` reading
each step's own prescribed+actual — **no `zip`**. Structural live edits (coach adds/removes
a set) cannot desync history, and each `SetRecord` carries a stable `sourceSetID`.

---

## 9. Conversational onboarding

Replace the 3-slide gate with a coach conversation (`CoachMode.onboarding`). A new user
may dictate/type a long unstructured account, provide a routine, build collaboratively, or
give minimal info. The coach records memories via `memory_add` and normally creates and
activates a plan via `plan_apply`. Onboarding is complete when an active plan exists OR the
user explicitly chooses to continue without one — NOT when slides were dismissed.
`hasOnboarded` is derived from that condition. Remove the launch-time `seedDefaultIfNeeded`;
keep "Upper Body A" as an explicit sample starter (a preset mutation) only.

---

## 10. Voice-first input

```
protocol TranscriptionProvider {
    var supportsPartials: Bool { get }
    func start() async throws                      // begins capture
    var partialText: AsyncStream<String> { get }   // live partials where available
    func stop() async throws -> String             // final transcript
    func cancel()
}
```
- `AppleSpeechTranscriber`: `SFSpeechRecognizer` + `AVAudioEngine`, on-device where
  supported, partial results. Default where available.
- `ElevenLabsTranscriber`: records audio, uploads to ElevenLabs STT, returns final text.
  Key in Keychain (`CoachSecrets`). Optional cloud provider.
- Settings: provider choice + credentials.
- Shared `VoiceInputController` + reusable UI: mic button, visible recording state, live
  partial transcript, cancel, failure recovery, **editable final transcript before submit**.
  Used in onboarding, coach chat, active-workout coach. The coach receives text regardless
  of provider — provider selection never touches the coach domain model.
- Info.plist: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`.

---

## 11. Honest, recoverable data ownership

- Add a Markdown **parser** beside `MarkdownGenerator`. Canonical restorable artifacts:
  `plan.md` (→ `PlanSnapshot`) and `sessions/*.md` (→ `WorkoutRecord`, which already
  carry prescribed+actual+rpe+notes). `README.md` is explicitly export-only (index).
- Tested round trip: snapshot → markdown → parse → equal snapshot; record → markdown →
  parse → equal record (modulo formatting/whitespace).
- Sync restore: on fresh install / second device, `pull()` reconstructs supported plans
  and history into SwiftData from the selected sync source.
- Conflict policy: **completed-workout history is factual and append-only** — never
  overwritten by external edits (a changed session file with new facts is added, not
  merged destructively; divergences are surfaced to the coach, not silently dropped).
  Plans use last-writer-wins, and an external plan change lands as a new plan revision.
- Do not silently treat externally changed Markdown as coach-reading material while
  leaving the DB permanently divergent: ingest reconstructs canonical records.

---

## 12. Migration (safe, no data loss)

`VersionedSchema` V1 (current 8 models) → V2 (adds `PlanSessionRecord`,
`PlanRevisionRecord`, `MemoryRecord`, `ActiveSessionRecord`, `PlanRecord.nextSessionID`;
`PlanBlockRecord` reparented plan→session). Custom migration stage:
1. For each existing `PlanRecord`, create one `PlanSessionRecord("Workout")` and reparent
   its blocks into it; set cursor to that session.
2. Seed `MemoryRecord`s from `AppSettings` goal/preference fields (`source: "migrated"`).
3. Write an initial `PlanRevisionRecord` per plan (baseline snapshot).
Preserve all `WorkoutRecord`/`ExerciseRecord`/`SetRecord`/`CoachNoteRecord`/`PlanRecord`
data. Test migration from a V1 store fixture.

---

## Slice order (each slice: build green + tests + verify, no parallel legacy path)

1. Canonical plan snapshot + `PlanOp`/`PlanEngine` (pure) + `PlanRepository` + revisions +
   restore + multi-session/cursor + V2 schema/migration. Rewire coach `edit_plan` path and
   editor UI onto it; delete `PlanEditInterpreter`.
2. `MemoryStore` general primitives + coach-context assembly reading memory; migrate settings.
3. App-level `CoachService` independent of WorkoutSession; new Rust tool set replacing the
   five narrow tools; Swift host dispatches to repositories.
4. Conversational text onboarding with direct plan activation; remove seed dependency.
5. Durable active-session persistence + resume/discard; stable prescribed-vs-actual.
6. Apple-native voice + provider abstraction, then ElevenLabs; voice UI in the three surfaces.
7. Real Markdown import/round-trip + sync restore + conflict policy.
8. Remove obsolete generators/interpreters/seed/duplicate context paths; update product spec.

## Tests (product invariants)
create-by-mutation · atomic deltas + stable ids · default apply · optional propose ·
revision history + restore · memory add/update/query/delete + context refresh · onboarding
→ active plan · active-session persist/resume · structural live edit preserves history ·
markdown round-trip + conflict · V1→V2 migration.
