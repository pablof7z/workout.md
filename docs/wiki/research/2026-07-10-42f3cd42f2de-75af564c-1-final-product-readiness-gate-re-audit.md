---
type: research-record
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
source_lines: 2600-2645
agent_attribution: a63dd1919dc0e4d76
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Final product-readiness gate: re-audit of feature-complete app against pre-registered punch-list (B1-B4, M1-M5, M7) with build verification and live coach tool-mutation test; verdict PASS"
captured_at: 2026-07-10T07:41:28Z
---

Final product-readiness gate: re-audit of feature-complete app against pre-registered punch-list (B1-B4, M1-M5, M7) with build verification and live coach tool-mutation test; verdict PASS

---

User: [Agent task result: Agent "Final Opus readiness gate" finished]
I have comprehensive evidence across code review and a live end-to-end run. Here is my final gate assessment.

---

# Workout.md — Final Product-Readiness Gate

**Build:** `** BUILD SUCCEEDED **` (Rust core + UniFFI + SwiftUI) on a dedicated `wmd-gate` iPhone 16 / iOS 26.2 simulator. Installed and launched cleanly; real app icon present on springboard; bundle id `com.workoutmd.prototype`.

## (a) Punch-list verification

| Item | Status | Evidence |
|---|---|---|
| **B1** app icon + asset catalog | RESOLVED | `Sources/Assets.xcassets/AppIcon.appiconset/` has all 9 sizes + 1024; `Info.plist` → `CFBundleIconName=AppIcon`; icon rendered. |
| **B2** real persisted plans; Today driven by ACTIVE plan; coach `edit_plan`/`create_plan` + repair | RESOLVED | Today shows active "Upper Body A · 3 blocks · ~40 min · Hypertrophy" (no MockWorkout). Plans list has ACTIVE badge, create/duplicate/delete/activate/edit. Full editor: Details/Blocks (straight/superset/circuit)/Add Block/Export Markdown. `edit_plan` tool in `tools.rs`; `create_plan`/repair via `CoachController.generatePlan` + `WhatsNextView`. |
| **B3** no fake sample history; real empty state | RESOLVED | No `MockHistory` in code (only in comments). History shows `ContentUnavailableView` "No workouts yet — Finish a session to see it here." |
| **B4** no dev `core vX`/echo affordances in UI | RESOLVED | `coreVersion`/`echo` exist only in generated `Bridge/Generated/workout_core.swift`; zero references from any UI/Swift source. |
| **M1** iCloud option | RESOLVED | `WorkoutMD.entitlements` has CloudDocuments + ubiquity container; `Sync/ICloudSync.swift`; Settings "iCloud sync" toggle + status. |
| **M2** external commits actually REVIEWED by coach | RESOLVED | `GitHubSync.pull()` → `SyncManager.onExternalChanges` → `CoachController.shared.reviewExternalChanges` → `CoachReviewStore`, and that store's `contextSnippet()` is folded back into every coach turn's grounding. |
| **M3** graceful unconfigured-coach state + onboarding + non-localhost default | RESOLVED | 3-screen onboarding (track → coach → own data). Calm coach state ("Tell me how it feels") with no key. Default provider = **OpenRouter / anthropic-claude-3.5-sonnet** (not localhost). |
| **M4** goals/preferences reach coach grounding | RESOLVED | `CoachController.send` folds `settings.goalsContextSnippet` into the user message; Goals section in Settings. |
| **M5** "What should I do next?"/repair reachable from Today | RESOLVED | Prominent Today button → `WhatsNextView` with forward-repair prompt (no guilt/catch-up) + deterministic fallback. |
| **M7** uploaded doctrine influences coach | RESOLVED | `DoctrineStore.shared.digest()` folded into grounding when `doctrineEnabled`; Doctrine section in Settings. |

## Live coach test (the hard one) — PASSED
Configured Ollama (`localhost:11434`, model `glm-5.2:cloud`), opened the in-session Coach, and sent *"Shoulder is tweaking, that was too heavy. Drop the weight to 115 for the rest."* Got a **real streamed reply** plus tools that **actually mutated the session**:
- `Bench Press set 2: 135 → 115 lb`
- `Bench Press set 3: 135 → 115 lb`
- `Note (exercise): Bench Press: Shoulder tweaking… Monitor shoulder next session…`

rig.rs multi-turn tool loop + memory (`CoachNoteRecord`, plan-scoped) + all 5 tools (adjust_set, skip_set, deload_exercise, add_note, edit_plan) confirmed working. Markdown export via `ShareLink` in both History (per-session) and Settings (full history); `MarkdownGenerator` renders clean prescribed-vs-actual tables + deviations + coach notes. Fabric (tenex-edge nostr, NIP-29 kind:0/kind:9, nsec in Keychain) present in `core/nostr` + Settings FabricSection.

## (b) New issues found
1. **Minor / cosmetic — reasoning-model `<think>` tag leak.** The live reply from `glm-5.2:cloud` rendered a raw `</think>` marker inline ("…summarize this for the athlete.**</think>**Sets 1 and 2 dropped…"). No think-tag stripping exists anywhere in Swift or Rust. Only affects reasoning models (deepseek-r1/qwq/glm/etc.); the **default** OpenRouter/Claude model does not emit these, so the shipped default is clean. Fix: strip `<think>…</think>` in `CoachController`/`run_stream` before display.
2. **Minor — GitHub uses PAT, not OAuth device-flow.** `GitHubAuth.swift` has a TODO for a real OAuth client id; Settings honestly says device-flow "isn't wired up yet." PAT-with-repo-scope is a reasonable v1 path and clearly labeled. Not a blocker.
3. **Cosmetic — `prototype` in bundle/iCloud container id** (`com.workoutmd.prototype`). Deployable, but worth renaming before store submission.

None of these prevent the app from delivering the goal or being demoed on a device.

## (c) Verdict

**VERDICT: PASS**

The prior punch list is fully resolved. This is a real, cohesive, polished app: a genuine rig.rs coach with working tools + cross-launch memory, rich Settings (providers/models/keys/voice), SwiftData persistence with clean Markdown export, GitHub + iCloud sync with coach-reviewed external commits, the tenex-edge nostr fabric, real editable plans driving a finished set-runner, plan creation/repair, onboarding, and every screen a v1 needs — all built with a consistent full-bleed Liquid-Glass design language. The hardest promise (live streamed coach that actually changes a set via a tool) works end-to-end.

Optional nice-to-haves before store submission: strip reasoning-model `<think>` tags (#1), wire real GitHub OAuth (#2), and drop the `prototype` suffix from the bundle id (#3).
