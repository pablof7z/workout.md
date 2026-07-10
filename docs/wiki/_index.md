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

## Research Records (3 records)

| Record | Date | Finding | Agent |
|--------|------|---------|-------|
| [2026-07-10-42f3cd42f2de-75af564c-1-opus-product-readiness-audit-static-code](research/2026-07-10-42f3cd42f2de-75af564c-1-opus-product-readiness-audit-static-code.md) | 2026-07-10 | Opus product-readiness audit: static code/build-bundle inspection against spec MVP must-haves; verdict NOT-YET with prioritized blocker/major/minor/polish punch list | subagent (Opus product-readiness audit) |
| [2026-07-10-42f3cd42f2de-75af564c-2-final-opus-readiness-gate-re-audit](research/2026-07-10-42f3cd42f2de-75af564c-2-final-opus-readiness-gate-re-audit.md) | 2026-07-10 | Final Opus readiness gate: re-audit with simulator build, live coach tool-loop test, and punch-list verification table; verdict PASS | subagent (Final Opus readiness gate) |
| [AGENTS](research/AGENTS.md) |  |  |  |

## Episode Cards (3 cards)

| Card | Date | Title | Salience | Status |
|------|------|-------|----------|--------|
| [2026-07-09-42f3cd42f2de-75af564c-1-html-web-prototype-native-swiftui-ios](episodes/2026-07-09-42f3cd42f2de-75af564c-1-html-web-prototype-native-swiftui-ios.md) | 2026-07-09 | HTML web prototype → native SwiftUI iOS app | reversal | active |
| [2026-07-09-42f3cd42f2de-75af564c-2-today-screen-interaction-model-list-view](episodes/2026-07-09-42f3cd42f2de-75af564c-2-today-screen-interaction-model-list-view.md) | 2026-07-09 | Today screen interaction model: list view → TikTok-style one-set-at-a-time runner | product | active |
| [2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first](episodes/2026-07-09-42f3cd42f2de-75af564c-3-circuit-superset-support-added-as-first.md) | 2026-07-09 | Circuit/superset support added as first-class data model | product | active |

## Nouns (10 entities)

| Noun | Name | Origin | Definition |
|------|------|--------|------------|
| [coach](nouns/coach.md) | Coach | extracted | Configurable policy, not a persona; default voice is dry, direct, sparse, configurable at global/block/methodology/workout/override levels. |
| [coach-context](nouns/coach-context.md) | Coach & context | extracted | The settings surface that doesn't feel like settings — where goals, preferences, constraints, uploaded doctrine, and coach instructions live, written in plain language and editable anytime; the knobs behind every AI decision. |
| [coach-screen](nouns/coach-screen.md) | Coach screen | extracted | A per-exercise, TikTok side panel (reached by swiping right) where a scripted keyword coach replies terse/dry and mutates upcoming sets. |
| [ghost-targets](nouns/ghost-targets.md) | ghost targets | extracted | Every prescribed number the user sees — an AI decision rendered as a plan, not as a bot. |
| [markdown](nouns/markdown.md) | Markdown | extracted | The storage/portability layer (the substrate), never the interface — every workout is a clean .md file exportable, syncable, and feedable to your own AI, but you never type it raw. |
| [plan-calendar](nouns/plan-calendar.md) | Plan / calendar | extracted | Not a rigid grid but a lightweight timeline of 'what's coming,' whose main job is to answer what's next when you return, especially after a gap — no red missed-days. |
| [tiktok-style-runner-app-concept](nouns/tiktok-style-runner-app-concept.md) | TikTok-style runner (app concept) | extracted | The core UI paradigm for Workout.md: one set per full-screen page, swipe down for next set, swipe right for the Coach screen, full-bleed backgrounds with hue per block. |
| [today-the-home](nouns/today-the-home.md) | Today (the home) | extracted | The default screen and 90% of usage — a vertical list of today's exercises with prescribed targets as ghosted placeholders; the whole screen is a big fillable form where you tap to log actuals. |
| [workout-md](nouns/workout-md.md) | Workout.md | extracted | A minimal-friction workout tracker where the wedge is fast tracking and AI is a planning layer behind the product, not a chatbot. |
| [workoutsession](nouns/workoutsession.md) | WorkoutSession | extracted | A shared @Observable (Observation framework) single source of truth owning mutable steps, currentStepID, per-set RPE, per-exercise transcripts, offerDeload, and deloaded state; all edit logic (adjustReps, skip, setEffort, sendCoachMessage, applyDeload, buildSummary) lives on it. |

