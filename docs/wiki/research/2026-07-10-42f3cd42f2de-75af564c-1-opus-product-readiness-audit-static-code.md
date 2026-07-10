---
type: research-record
date: 2026-07-10
session: 42f3cd42-f2de-49b4-abff-fc10d0bedf8f
transcript: /Users/pablofernandez/.claude/projects/-Users-pablofernandez-Work-workout-md/42f3cd42-f2de-49b4-abff-fc10d0bedf8f.jsonl
source_lines: 2124-2243
agent_attribution: subagent (Opus product-readiness audit)
has_preregistered_criteria: true
has_method: true
has_structured_report: true
characterization: "Opus product-readiness audit: static code/build-bundle inspection against spec MVP must-haves; verdict NOT-YET with prioritized blocker/major/minor/polish punch list"
captured_at: 2026-07-10T04:57:54Z
---

Opus product-readiness audit: static code/build-bundle inspection against spec MVP must-haves; verdict NOT-YET with prioritized blocker/major/minor/polish punch list

---

User: [Agent task result: Agent "Opus product-readiness audit" finished]
I now have a comprehensive picture from a thorough static audit plus inspection of the already-built device bundle. I have enough to deliver the prioritized punch list without a fresh build (I inspected the existing `build-device/.../WorkoutMD.app` to confirm the icon/asset findings).

---

# Workout.md — Product-Readiness Audit

**Method:** Read the product spec, all of `WorkoutMD/Sources/**`, and `core/workout-core/src/**`; inspected the committed device build bundle (`build-device/.../WorkoutMD.app`) and `Info.plist`; reviewed git history. No code modified.

**Headline:** The *engineering substrate* is genuinely real and impressive — the Rust core (rig.rs streaming coach with a real 5-tool loop + host callbacks, nostr/NIP-29 fabric with real signing/publish/subscribe, GitHub REST sync with retry queue, SwiftData persistence, clean Markdown). But the **product on top of it is a single-workout demo**: the whole app can only ever run one hardcoded "Upper Body A", ships fake sample data and a dev proof-of-life label, has no app icon, no onboarding, no plan creation, and several headline goal features are scaffolded-but-not-wired. It reads as a polished *tech demo*, not a finished shippable app.

---

## BLOCKERS

**B1. No app icon / no asset catalog at all.**
There is no `.xcassets` anywhere in the repo, and the built `WorkoutMD.app` bundle contains no `AppIcon`/`Assets.car`. On a real iPhone home screen this shows the blank default grey icon. A "deployed to iPhone, finished app" fails at the springboard.
*Area:* `project.yml` (no asset catalog source), whole project.
*Fix:* Add `Sources/Assets.xcassets` with a full `AppIcon` set (and an accent color), reference it in `project.yml`, set `ASSETCATALOG_COMPILER_APPICON_NAME`.

**B2. The entire app is a single hardcoded `MockWorkout`.**
`Models.swift` `MockWorkout` ("Upper Body A") is the *only* workout. `TodayView` always shows `MockWorkout.name/summary`; `WorkoutSession()` always inits from `MockWorkout.steps`; `RunnerView` passes `MockWorkout.name` to the list. There is no plan model persisted, no way to create/select/edit a workout, no "start blank / from previous / from template / from a goal." `edit_plan` explicitly no-ops ("out of scope for this prototype's static MockWorkout plan graph… records the instruction as a note"). This fails spec MVP must-haves *Basic plan creation, Basic plan adjustment, Track an unplanned/modified workout, Repair next workout*, and the whole "real app with real features" goal.
*Area:* `Models.swift` (MockWorkout, WorkoutSession.init), `TodayView.swift`, `RunnerView.swift`, `Models.swift applyEditPlan`.
*Fix:* Introduce a persisted Plan/Workout model + a plan library/selection surface; let the coach's `edit_plan`/plan-creation actually mutate a real plan graph; drive Today/Runner from the selected plan, not `MockWorkout`.

**B3. Ships fake sample data seeded into History on first launch.**
`MockHistory.seedIfNeeded` inserts two fabricated `WorkoutRecord`s (labeled "SAMPLE") on first run. A finished app must not seed fake history.
*Area:* `MockHistory.swift`, `WorkoutMDApp.swift` (`MockHistory.seedIfNeeded` call).
*Fix:* Remove the seed (or gate strictly behind `#if DEBUG` and never in Release). Provide a real empty-state instead (History already has a good `ContentUnavailableView`).

**B4. Dev proof-of-life affordances visible in shipping UI.**
`TodayView` renders a persistent `core v{coreVersion()}` label bottom-right, and `.onAppear` runs `WorkoutCore().greeting()` + `echo("ping")` with a `print(...)`. The `WorkoutCore` object/`echo`/`greeting`/`core_version` are pure proof-of-pipeline scaffolding.
*Area:* `TodayView.swift` (lines ~16-21, ~66-78), `core/workout-core/src/lib.rs`.
*Fix:* Delete the version label, the onAppear FFI print, and the `WorkoutCore` demo object.

---

## MAJOR

**M1. iCloud option entirely absent.** The goal explicitly requires "an iCloud option." There is no CloudKit, no `NSUbiquitous*`, no iCloud entitlement; SwiftData uses a plain local `ModelConfiguration`; all Keychain items are deliberately `…ThisDeviceOnly`. Nothing to toggle.
*Fix:* Add a CloudKit-backed `ModelConfiguration` option (or an iCloud Drive document-sync option for the Markdown), gated by a Settings toggle + entitlement.

**M2. "Agent reviews new commits" is fetched but not wired to the coach.** `GitHubSync.pull()` correctly detects external (non-bot) commits and calls `onExternalChanges`, and `SyncManager` re-exposes `onExternalChanges` — but nothing ever sets it to feed the coach. Code comments admit it: "Wiring an actual review UI/flow is a later workstream — this closure is the plug point." So the headline "agent reviews new commits / pull-ingest external edits" goal is only half-built (ingest yes, review no).
*Area:* `SyncManager.swift`, `GitHubSync.swift`, `CoachController.swift`.
*Fix:* Wire `SyncManager.onExternalChanges` to a coach review turn (or an inbox surface) that ingests the changed Markdown and produces a review note.

**M3. First-run coach is broken by default and has no graceful unconfigured state.** Default provider is `.ollama` at `http://localhost:11434` (`AppSettings.init`). On a physical iPhone that's unreachable → every coach turn fails with a raw connection error dumped into the transcript ("Error: failed to start Ollama client…"). With OpenRouter + no key it 401s the same way. There is no onboarding and no "set up your coach" empty state — `CoachView` always seeds a chatty transcript and lets you send. Goal explicitly demanded "behaves sanely with no key set."
*Area:* `AppSettings.swift` (default provider), `CoachController.swift`, `CoachView.swift`.
*Fix:* Detect unconfigured/unreachable coach and show a calm inline "Configure a provider in Settings" state instead of a raw error; pick a sensible default (e.g. OpenRouter, empty until key set) rather than an on-device localhost that can never work.

**M4. Configured Goals/Preferences never reach the coach.** Settings collects `primaryGoal`, `sessionLengthMinutes`, `dislikedExercises` and the footer claims "The coach sees these as grounding context" — but `CoachController.send` builds the user message from `session.coachContext + fabric + note` only, and `effectiveSystemPrompt` appends only the verbosity suffix. None of the goals/prefs are injected. The entire Goals section is decorative. Spec §6.3 (goals, preferences, constraints, doctrine) is largely unfulfilled.
*Area:* `CoachController.swift`, `AppSettings.effectiveSystemPrompt`, `SettingsView` GoalsSection.
*Fix:* Fold goals/prefs/dislikes (and later doctrine) into the system prompt or grounding block.

**M5. No surface for the #1 planning job: "What should I do next?"** The coach is only reachable by swiping inside a *running* session (`SessionView` pager). There is no coach/plan-repair entry point from Today. Spec §8.1 calls "What should I do next?" the most important planning output; plan repair after absence (§5.4, §11) has no home.
*Fix:* Add a coach/plan entry point on Today (plan next session, repair after missed days) that isn't gated behind starting a workout.

**M6. "Providers/models per agent/tool" not implemented.** The goal asked for rich Settings to configure provider/model *per agent/tool*. Settings exposes exactly one coach provider+model. The nostr "coach" agent has no model config of its own; tools have none.
*Fix:* If in scope, add per-role model config; at minimum acknowledge/trim the goal.

**M7. Uploaded training doctrine absent.** Spec §5.7/§6.3 "use my 5/3/1 notes / hypertrophy doc / rehab guidance" — no document upload or doctrine influence anywhere.
*Fix:* Add a doctrine document store that feeds coach grounding (later-tier per spec, but it's a named goal input).

**M8. GitHub "Sign in with GitHub" is dead.** `GitHubAuth` device flow is fully coded but `deviceFlowClientID = "TODO_REGISTER_GITHUB_OAUTH_APP_CLIENT_ID"`, so only PAT paste works. Settings footer admits it "isn't wired up yet." Pasting a PAT is a rough table-stakes experience for a shipping consumer app.
*Fix:* Register an OAuth App and drop in the client id, or remove the scaffold and make the PAT flow first-class with clear guidance.

---

## MINOR

**m1. "Glass gear/history buttons fail to paint on first frame" (reported bug) is plausible and unmitigated.** `TodayView`'s `SettingsButton`/`HistoryButton` are `.buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)` inside a `ZStack` whose `.onAppear` does synchronous FFI work — a known iOS 26 first-frame glass-materialization pattern. Same idiom on Coach header. (Couldn't reproduce without a run, but the setup matches the report.)
*Fix:* Wrap the corner buttons in a `GlassEffectContainer` (as done in `CoachView.inputBar`), and move the FFI print off `onAppear`.

**m2. Stale "no Settings screen yet" comments.** `SyncManager` ("No Settings screen yet… debug affordance"), `GitHubAuth` ("There is no Settings screen yet"), `SyncStatus` ("debug affordance in HistoryView today") are all wrong now that Settings exists — misleading and read as unfinished.
*Fix:* Update the doc comments.

**m3. Weight unit hardcoded to `lb`.** No kg option anywhere (`SetTarget.displayString`, Markdown, fabric summaries). Non-US users can't use it properly.

**m4. `MarkdownGenerator.renderPlan` is dead code** until real plans exist (ties to B2).

**m5. Dynamic Type partial.** Many surfaces use fixed `.font(.system(size:))` (runner controls, coach corner buttons, transcript glyphs), which won't scale with Accessibility text sizes. VoiceOver labels are generally good, which is a plus.

**m6. Fabric default UX fragility.** A closed NIP-29 channel requires the user to run `tenex-edge channel add` in a CLI outside the app before the coach can post; until then outbound posts land in `lastPublishError`. Reasonable per design, but the happy path depends on an external CLI step with no in-app verification.

---

## POLISH

- **p1.** No custom launch screen — `UILaunchScreen_Generation: YES` yields a blank generated screen; a finished app usually brands this.
- **p2.** Coach memory is keyed by bare exercise *name* globally (`historyJSON(for: exercise)`), so "Bench Press" memory bleeds across different workouts/plans and forever; no recency/session scoping beyond a 24-item window.
- **p3.** `edit_plan`/`add_note` confirmations are shown only in the transcript of the currently-scoped exercise even when they target another exercise — mildly confusing.
- **p4.** Fabric inbound authors shown as truncated hex pubkey (`authorShort`), never resolved to kind:0 names — fine for a dev, opaque for a user.
- **p5.** DEBUG "Own this channel" button is correctly `#if DEBUG`-gizmoed — good; just confirming it won't ship.

---

## What's genuinely solid (so the polish crew doesn't rebuild it)
- Rust coach: real rig.rs multi-turn streaming, 5 real tools routed to a Swift `CoachHost` that actually mutates `WorkoutSession` upcoming sets, key redaction, unconfigured-error path, good tests.
- Nostr fabric: real identity gen/import, kind:0/kind:9, group create/lock/put-user, publish-checked with duplicate handling, subscription sink — mirrors tenex-edge wire format.
- GitHub sync: commit-per-workday path convention, idempotent PUT, README index, external-change detection, offline retry queue persisted to disk.
- Persistence + Markdown: clean front-matter, prescribed-vs-actual tables, deviations counted, export via `ShareLink`. History screen is tasteful and uses proper native `List` (correctly distinct from the full-bleed runner).
- Threading discipline (main-hop marshaling of Rust callbacks) is careful and correct.

---

## VERDICT: **NOT-YET**

It is not a finished, polished app that meets the goal. It's a strong technical skeleton wrapped around a one-workout demo with shipping-blocking dev leftovers.

**Shortest path to PASS (must-fix):**
1. **B1** add a real app icon + asset catalog.
2. **B2** make workouts real — a persisted plan model + creation/selection, and wire `edit_plan`/plan-creation to it (kills the single-`MockWorkout` demo).
3. **B3 + B4** strip fake sample history and the `core vX` / echo dev affordances.
4. **M3** graceful unconfigured-coach state + a default provider that can actually work on-device; add a minimal first-run/onboarding.
5. **M2** wire external-commit review to the coach (the goal's "agent reviews new commits").
6. **M1** add the iCloud option.
7. **M4** actually pass configured goals/preferences to the coach.
8. **M5** give plan-repair / "what's next" a home outside a running session.

M6/M7/M8 and the MINOR/POLISH items can follow, but the eight above are the gate between "impressive demo" and "finished app that meets the stated goal."
