# Wiki Index

> Derived cache — do not hand-edit. Rebuilt by proactive-context after each capture.

Last updated: 2026-07-10

## agent-system (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [agent-workflow-and-roles](guides/agent-workflow-and-roles.md) | Agent Workflow and Roles | Coding is done by Sonnet agents, device testing by Haiku agents, and product-readiness is gated by an Opus agent judge | capture | warm | 2026-07-09 | agent-system |

## build-configuration (2 guides)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [code-signing-and-provisioning](guides/code-signing-and-provisioning.md) | Code Signing and Provisioning | Builds use automatic code signing that works for both simulator and device deployment | capture | warm | 2026-07-09 | build-configuration |
| [native-ios-build-setup](guides/native-ios-build-setup.md) | Native iOS Build Setup | The prototype is built as a real native iOS SwiftUI app targeting the iOS 26 SDK with real Liquid Glass APIs, not a web emulation | capture | warm | 2026-07-09 | build-configuration |

## coach-policy (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [coach-configuration-and-behavior](guides/coach-configuration-and-behavior.md) | Coach Configuration and Behavior | The coach is configurable policy, not a persona | capture | warm | 2026-07-09 | coach-policy |

## data-model (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [data-model-and-markdown-storage](guides/data-model-and-markdown-storage.md) | Data Model and Markdown Storage | Workout data is stored as portable Markdown, supporting both hosted and local AI providers | capture | warm | 2026-07-09 | data-model |

## ui-components (2 guides)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [effort-feedback-dial](guides/effort-feedback-dial.md) | Effort Feedback Dial | The user can provide effort feedback easily on the current set | capture | warm | 2026-07-09 | ui-components |
| [glass-ui-design-system](guides/glass-ui-design-system.md) | Glass UI Design System | The app uses the liquid-glass-design skill's visual language — translucent blurred panels, specular top-edge highlights, a floating glass tab bar, and press-sca | capture | warm | 2026-07-09 | ui-components |

## ui-screens (1 guide)

| Slug | Title | Summary | Tags | Volatility | Verified | Topic |
|------|-------|---------|------|------------|----------|-------|
| [coach-screen-and-plan-mutation](guides/coach-screen-and-plan-mutation.md) | Coach Screen and Plan Mutation | Swipe right on the runner opens a per-exercise Coach screen — a TikTok-style side panel where the user writes how it felt in plain language and the coach replie | capture | warm | 2026-07-09 | ui-screens |

## Research Records (4 records)

| Record | Date | Finding | Agent |
|--------|------|---------|-------|
| [2026-07-10-42f3cd42f2de-75af564c-1-first-opus-code-audit-systematic-evaluation](research/2026-07-10-42f3cd42f2de-75af564c-1-first-opus-code-audit-systematic-evaluation.md) | 2026-07-10 | First Opus code audit: systematic evaluation of app against spec MVP must-haves, categorized findings (4 BLOCKERS, 8 MAJOR, 6 MINOR, 5 POLISH), verdict NOT-YET with prioritized fix path | opus-audit-agent |
| [2026-07-10-42f3cd42f2de-75af564c-1-opus-product-readiness-audit-static-code](research/2026-07-10-42f3cd42f2de-75af564c-1-opus-product-readiness-audit-static-code.md) | 2026-07-10 | Opus product-readiness audit: static code/build-bundle inspection against spec MVP must-haves; verdict NOT-YET with prioritized blocker/major/minor/polish punch list | subagent (Opus product-readiness audit) |
| [2026-07-10-42f3cd42f2de-75af564c-2-final-opus-readiness-gate-re-audit](research/2026-07-10-42f3cd42f2de-75af564c-2-final-opus-readiness-gate-re-audit.md) | 2026-07-10 | Final Opus readiness gate: re-audit with simulator build, live coach tool-loop test, and punch-list verification table; verdict PASS | subagent (Final Opus readiness gate) |
| [AGENTS](research/AGENTS.md) |  |  |  |

## Episode Cards (20 cards)

| Card | Date | Title | Salience | Status |
|------|------|-------|----------|--------|
| [2026-07-09-42f3cd42f2de-75af564c-1-html-web-prototype-native-swiftui-ios](episodes/2026-07-09-42f3cd42f2de-75af564c-1-html-web-prototype-native-swiftui-ios.md) | 2026-07-09 | HTML web prototype → native SwiftUI iOS app | reversal | active |
| [2026-07-09-42f3cd42f2de-75af564c-2-today-screen-interaction-model-list-view](episodes/2026-07-09-42f3cd42f2de-75af564c-2-today-screen-interaction-model-list-view.md) | 2026-07-09 | Today screen interaction model: list view → TikTok-style one-set-at-a-time runner | product | active |
| [2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first](episodes/2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first.md) | 2026-07-09 | Circuit/superset support added as first-class data model | product | superseded |
| [2026-07-10-42f3cd42f2de-75af564c-1-real-persisted-plan-model-replaces-hardcoded](episodes/2026-07-10-42f3cd42f2de-75af564c-1-real-persisted-plan-model-replaces-hardcoded.md) | 2026-07-10 | Real persisted plan model replaces hardcoded MockWorkout demo | reversal | active |
| [2026-07-10-42f3cd42f2de-75af564c-2-coach-grounding-architecture-goals-doctrine-external](episodes/2026-07-10-42f3cd42f2de-75af564c-2-coach-grounding-architecture-goals-doctrine-external.md) | 2026-07-10 | Coach grounding architecture: goals + doctrine + external-commit review folded into every coach turn | architecture | active |
| [2026-07-10-42f3cd42f2de-75af564c-3-reasoning-model-think-tag-leak-root](episodes/2026-07-10-42f3cd42f2de-75af564c-3-reasoning-model-think-tag-leak-root.md) | 2026-07-10 | Reasoning-model think-tag leak: root cause and streaming-safe ThinkStripper | root-cause | active |
| [2026-07-10-42f3cd42f2de-75af564c-4-icloud-entitlement-triggers-swiftdata-cloudkit-auto](episodes/2026-07-10-42f3cd42f2de-75af564c-4-icloud-entitlement-triggers-swiftdata-cloudkit-auto.md) | 2026-07-10 | iCloud entitlement triggers SwiftData CloudKit auto-detection crash | root-cause | active |
| [2026-07-10-42f3cd42f2de-75af564c-5-set-input-ui-redesign-tap-to](episodes/2026-07-10-42f3cd42f2de-75af564c-5-set-input-ui-redesign-tap-to.md) | 2026-07-10 | Set-input UI redesign: tap-to-reveal converges to floating-lines with reps and weight both editable, centered | product | active |
| [2026-07-10-42f3cd42f2de-75af564c-6-nip-29-join-request-kind-9021](episodes/2026-07-10-42f3cd42f2de-75af564c-6-nip-29-join-request-kind-9021.md) | 2026-07-10 | NIP-29 join request (kind 9021) for requesting channel access when not a member | product | active |
| [2026-07-10-42f3cd42f2de-75af564c-7-productization-finishing-pass-app-icon-onboarding](episodes/2026-07-10-42f3cd42f2de-75af564c-7-productization-finishing-pass-app-icon-onboarding.md) | 2026-07-10 | Productization finishing pass: app icon, onboarding, dev-scaffolding removal, default provider and no-key coach state | product | active |
| [2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-team-switched-from-personal](episodes/2026-07-10-43fd928f6da0-b40f7d8e-1-code-signing-team-switched-from-personal.md) | 2026-07-10 | Code signing team switched from personal free team to paid SANITY ISLAND LLC to preserve bundle ID | architecture | active |
| [2026-07-10-43fd928f6da0-b40f7d8e-1-switch-ios-project-from-no-signing](episodes/2026-07-10-43fd928f6da0-b40f7d8e-1-switch-ios-project-from-no-signing.md) | 2026-07-10 | Switch iOS project from no-signing/simulator to paid-team code signing | architecture | superseded |
| [2026-07-10-576bd63b163a-031f8906-1-overlay-after-ignoressafearea-double-counts-safe](episodes/2026-07-10-576bd63b163a-031f8906-1-overlay-after-ignoressafearea-double-counts-safe.md) | 2026-07-10 | Overlay-after-ignoresSafeArea double-counts safe-area insets | root-cause | superseded |
| [2026-07-10-576bd63b163a-031f8906-1-overlay-safe-area-double-count-root](episodes/2026-07-10-576bd63b163a-031f8906-1-overlay-safe-area-double-count-root.md) | 2026-07-10 | Overlay safe-area double-count root cause for top pill overlap | root-cause | active |
| [2026-07-10-576bd63b163a-031f8906-1-swiftui-overlay-safe-area-double-counting](episodes/2026-07-10-576bd63b163a-031f8906-1-swiftui-overlay-safe-area-double-counting.md) | 2026-07-10 | SwiftUI overlay safe-area double-counting root cause | root-cause | superseded |
| [2026-07-10-576bd63b163a-031f8906-2-compact-liquid-glass-toolbar-replaces-oversized](episodes/2026-07-10-576bd63b163a-031f8906-2-compact-liquid-glass-toolbar-replaces-oversized.md) | 2026-07-10 | Compact Liquid Glass toolbar replaces oversized effort bar | product | active |
| [2026-07-10-576bd63b163a-031f8906-2-effort-control-redesigned-from-oversized-bar](episodes/2026-07-10-576bd63b163a-031f8906-2-effort-control-redesigned-from-oversized-bar.md) | 2026-07-10 | Effort control redesigned from oversized bar to compact toolbar | product | superseded |
| [2026-07-10-576bd63b163a-031f8906-3-countdown-generalized-to-all-timed-pages](episodes/2026-07-10-576bd63b163a-031f8906-3-countdown-generalized-to-all-timed-pages.md) | 2026-07-10 | Countdown generalized to all timed pages | product | superseded |
| [2026-07-10-576bd63b163a-031f8906-3-rest-countdown-generalized-to-all-timed](episodes/2026-07-10-576bd63b163a-031f8906-3-rest-countdown-generalized-to-all-timed.md) | 2026-07-10 | Rest countdown generalized to all timed pages | product | active |
| [2026-07-10-576bd63b163a-031f8906-3-rest-page-timer-generalized-from-static](episodes/2026-07-10-576bd63b163a-031f8906-3-rest-page-timer-generalized-from-static.md) | 2026-07-10 | Rest page timer generalized from static number to live countdown ring | product | superseded |

## Nouns (34 entities)

| Noun | Name | Origin | Definition |
|------|------|--------|------------|
| [coach](nouns/coach.md) | Coach | extracted | Configurable policy, not a persona; default voice is dry, direct, sparse, configurable at global/block/methodology/workout/override levels. |
| [coach-agent-nostr](nouns/coach-agent-nostr.md) | Coach agent (nostr) | extracted | Gets its own nsec, its own kind:0 profile, and talks over kind:9 (instead of kind:1) on a tenex-edge NIP-29 channel the user configures — sharing training context with the user's other agents. |
| [coach-context](nouns/coach-context.md) | Coach & context | extracted | The settings surface that doesn't feel like settings — where goals, preferences, constraints, uploaded doctrine, and coach instructions live, written in plain language and editable anytime; the knobs behind every AI decision. |
| [coach-screen](nouns/coach-screen.md) | Coach screen | extracted | A per-exercise, TikTok side panel (reached by swiping right) where a scripted keyword coach replies terse/dry and mutates upcoming sets. |
| [coachview](nouns/coachview.md) | CoachView | extracted | The scripted mock coach, scoped to the current exercise. Full-bleed dark (same aesthetic as the runner — NOT a sheet, NOT web cards). The user types a plain-language note; a local keyword policy appends a terse, dry coach reply and applies a concrete change to the shared WorkoutSession, shown as a distinct applied-diff line. The coach voice is dry and direct — no pep talk. |
| [controlsview](nouns/controlsview.md) | ControlsView | extracted | The floating glass control cluster docked to the bottom safe area. Intentionally light after interaction rework: an expressive effort rating, the reps stepper (rep sets only), and a small Skip. No Log & Next (advancing is a swipe down); no Note button. Besides the coach cue pill, the only place in the runner that uses Liquid Glass — reserved for floating controls, never content. |
| [doneview](nouns/doneview.md) | DoneView | extracted | Terse, calm completion screen. No confetti, no streaks — just a summary and a way back to Today. |
| [effortcontrol](nouns/effortcontrol.md) | EffortControl | extracted | An expressive, interactive effort input that replaces the old Easy/Moderate/Hard pills. Collapsed it's a compact glass capsule ('Rate effort' or the committed value recolored); tapping morphs it into an interactive glass scale mapping RPE 6–10 with detents and haptics, recording the value into the shared WorkoutSession. |
| [exercise](nouns/exercise.md) | Exercise | extracted | A single exercise movement with its coaching cue and target for a set. `target` is `var` so the coach and the reps stepper can edit upcoming sets live through the shared session. |
| [ghost-targets](nouns/ghost-targets.md) | ghost targets | extracted | Every prescribed number the user sees — an AI decision rendered as a plan, not as a bot. |
| [inline-nudges](nouns/inline-nudges.md) | Inline nudges | extracted | When you miss reps twice or flag pain, a single quiet suggestion appears in context (e.g. 'drop set 3 to 115?') that you accept/ignore/override — a diff, not a conversation. |
| [kind-9](nouns/kind-9.md) | kind:9 | extracted | The nostr event kind the coach agent uses to communicate on tenex-edge, with ["h", channel] tags — where tenex-edge is settling on for chat, replacing kind:1. |
| [markdown](nouns/markdown.md) | Markdown | extracted | The storage/portability layer (the substrate), never the interface — every workout is a clean .md file exportable, syncable, and feedable to your own AI, but you never type it raw. |
| [markdown-in-this-project](nouns/markdown-in-this-project.md) | Markdown (in this project) | extracted | The substrate, never the interface. Under the hood every workout is a clean .md file exportable and syncable, but you never type it. |
| [moodkey](nouns/moodkey.md) | MoodKey | extracted | A key that maps each movement to a gradient/glow color used by BackgroundView for the full-bleed runner page background. |
| [onboardingview](nouns/onboardingview.md) | OnboardingView | extracted | A calm, full-bleed, three-screen first-run sequence: track → coach → own your data. Shown once (gated by AppSettings.hasOnboarded) before the athlete ever sees Today. Reuses the same BackgroundView mood-gradient language as the rest of the app rather than introducing a separate onboarding visual style, per the no-cards, full-bleed doctrine. |
| [plan-calendar](nouns/plan-calendar.md) | Plan / calendar | extracted | Not a rigid grid but a lightweight timeline of 'what's coming,' whose main job is to answer what's next when you return, especially after a gap — no red missed-days. |
| [runner-tiktok-style](nouns/runner-tiktok-style.md) | Runner (TikTok-style) | extracted | One set per full-screen page, tap or swipe to advance — you only see the set you need to do next, with optional coach cues attached per exercise. |
| [runnerview](nouns/runnerview.md) | RunnerView | extracted | The hero of the app: a full-screen vertical pager where each page is exactly one set (or a rest beat). Reads steps and current position from the shared WorkoutSession. The paging ScrollView spans the entire device height via ignoresSafeArea; floating glass controls are overlays, never safeAreaInset. Advancing between sets is a swipe down — no Log & Next button. |
| [sessionview](nouns/sessionview.md) | SessionView | extracted | TikTok-style horizontal pager with two pages: the Coach screen on the LEFT and the runner on the RIGHT, defaulting to the runner. Swiping RIGHT reveals the Coach (scoped to the current exercise); swiping LEFT returns to the runner. Horizontal page swipe and runner's vertical set-paging operate on perpendicular axes so they don't deadlock. |
| [settarget](nouns/settarget.md) | SetTarget | extracted | What the lifter is meant to hit for a given set: either a rep/weight target or a timed hold. |
| [steppageview](nouns/steppageview.md) | StepPageView | extracted | The single most important screen in the app: one page = one set, with full-bleed background, big calm typography, a quiet coach cue, and — inside a group — a round counter and mini-map. |
| [tiktok-style-runner-app-concept](nouns/tiktok-style-runner-app-concept.md) | TikTok-style runner (app concept) | extracted | The core UI paradigm for Workout.md: one set per full-screen page, swipe down for next set, swipe right for the Coach screen, full-bleed backgrounds with hue per block. |
| [today-screen](nouns/today-screen.md) | Today screen | extracted | The home and default 90% of usage — a vertical list of today's exercises with prescribed targets as ghosted placeholders; a big fillable form where logging a set is one or two taps. |
| [today-the-home](nouns/today-the-home.md) | Today (the home) | extracted | The default screen and 90% of usage — a vertical list of today's exercises with prescribed targets as ghosted placeholders; the whole screen is a big fillable form where you tap to log actuals. |
| [todayview](nouns/todayview.md) | TodayView | extracted | The minimal 'Today' landing screen — full-bleed, calm, one clear action: Start. |
| [topstripmetrics](nouns/topstripmetrics.md) | TopStripMetrics | extracted | Sizing enum for the floating TopContextStrip pill in RunnerView, shared with StepPageView so its topReserve is derived from the pill's actual rendered geometry instead of a guessed constant. Defines topOffset=6, height=34 (caption-weight text + padding), clearance=16, totalReserve=56. |
| [what-should-i-do-next-affordance](nouns/what-should-i-do-next-affordance.md) | What should I do next? affordance | extracted | One button/utterance that regenerates the next session from current reality — the plan-repair engine surfaced as a single action. |
| [whatsnextview](nouns/whatsnextview.md) | WhatsNextView | extracted | The 'what should I do next?' surface: a prominent Today entry (outside a running session) that asks the coach to propose or REPAIR the next session from recent history/goals. Forward-only — no guilt, no catch-up, no streaks — so a gap in training is surfaced as 'here's the next useful session,' never as a red missed-days count. Falls back to a deterministic coach-independent repair when no coach provider is reachable. |
| [workout-md](nouns/workout-md.md) | Workout.md | extracted | A minimal-friction workout tracker where the wedge is fast tracking and AI is a planning layer behind the product, not a chatbot. |
| [workout-md-ios-prototype](nouns/workout-md-ios-prototype.md) | workout-md-ios-prototype | extracted | A native SwiftUI iOS 26 Liquid Glass prototype for Workout.md using mock data with no backend |
| [workoutblock-blockkind](nouns/workoutblock-blockkind.md) | WorkoutBlock / BlockKind | extracted | A model for straight-sets vs. superset/circuit groups, with rounds and an inline movement mini-map (A1 ▶ A2 …). |
| [workoutlistview](nouns/workoutlistview.md) | WorkoutListView | extracted | The full workout overview presented as a sheet from the top context strip. Because a sheet is a native surface, a grouped List with rows is the correct idiom here — this is NOT the full-bleed, no-cards runner. Rows are grouped by block, the current step is highlighted, and tapping any row jumps the pager to that step. |
| [workoutsession](nouns/workoutsession.md) | WorkoutSession | extracted | A shared @Observable (Observation framework) single source of truth owning mutable steps, currentStepID, per-set RPE, per-exercise transcripts, offerDeload, and deloaded state; all edit logic (adjustReps, skip, setEffort, sendCoachMessage, applyDeload, buildSummary) lives on it. |

