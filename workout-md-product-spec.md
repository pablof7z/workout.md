# Workout.md Product Spec

Version: 0.2
Status: Draft  
Scope: High-level product specification only. This document intentionally avoids architecture, implementation design, and screen-level design.

> **v0.2 settled decisions.** Several previously-open questions are now settled and
> implemented. In summary (details in §19): coach-generated plan changes **apply by
> default**, with optional unapplied **proposals** when iterating; plans are **versioned
> and recoverable**; the coach has **general durable memory**; the agent acts through a
> small set of **general plan/memory/session primitives** (not narrow per-task tools);
> **onboarding is a coach conversation**, not an intro-slide gate; and **voice input is
> part of v1**. Where earlier sections below still read as open, §19 governs.

## 1. Product Summary

Workout.md is a minimal-friction workout tracker with AI-assisted planning.

The app helps users track workouts quickly through structured, rich inputs while storing the underlying workout data in clean, portable Markdown. AI is used as a planning and adaptation layer over the user’s goals, training history, preferences, constraints, and uploaded training doctrine. The AI should not feel like a chatbot or companion; it should mostly operate behind the product, helping the user plan better workouts, adapt when reality diverges from the plan, and keep training moving forward.

The product should feel like:

> I open it, train, enter what happened, and the app keeps my future plan sane.

It should not feel like:

> I manage a database, write Markdown manually, chat with a coach, maintain a productivity system, or work for the app.

## 2. Core Product Job

The primary job is:

> Help the user track workouts with minimal friction.

The secondary job is:

> Help the user plan and adapt workouts using personal context.

Planning is important, but tracking is the product’s wedge. The app must first be excellent at helping the user record what actually happened during a workout. Planning and AI exist to make that tracking loop more useful, not to turn the app into a generic AI fitness coach.

## 3. Product Principles

### 3.1 Tracking-first

The app must prioritize fast workout entry over all other workflows. The user should not need to type raw Markdown, maintain a complex plan manually, or repeatedly explain context.

### 3.2 Rich inputs, Markdown output

Markdown is the storage and interoperability layer, not the primary interaction layer. The user should interact with structured controls, fields, selectors, quick edits, counters, notes, and simple overrides. Behind that, the app should produce clean Markdown that can be synced, exported, searched, and consumed by external AI systems.

### 3.3 The app absorbs mess

Workouts rarely go exactly as planned. The app should treat deviations as normal. Missed reps, skipped exercises, substituted movements, time constraints, fatigue, pain, missed workouts, and goal changes should be easy to record and should feed into future planning.

### 3.4 AI is a planning layer, not a chatbot

The AI should not be the main surface of the product. It should be used when useful: creating plans, adapting plans, reacting to workout performance, summarizing progress, and applying user-defined coaching rules. It should ask direct questions only when necessary.

### 3.5 Configurable coaching policy

The “coach” is not a character. It is a configurable planning policy over the user’s training data. Users should be able to define how it makes decisions, what it optimizes for, what training materials it should consider, and how direct or verbose it should be.

### 3.6 Data ownership

The user’s workout history and plans should not be trapped in a proprietary silo. Data should remain useful outside the app and available to the user’s broader personal AI or productivity system.

### 3.7 Low cognitive load

The product should optimize for users who benefit from low-friction, forgiving systems, including ADHD/2e users, without branding itself narrowly as an ADHD product.

## 4. Target User

The initial target user is someone who wants a serious but minimal workout tracker that supports planning, structured logging, and personal data ownership.

The user may:

- train for strength, hypertrophy, conditioning, fat loss, general fitness, or functional strength;
- want a plan, but frequently need to modify it;
- dislike social fitness apps, streak mechanics, and gamified pressure;
- want workout data to be exportable and useful outside the app;
- want AI assistance without chatting with a coach persona;
- need a system that keeps working after missed sessions, interruptions, or inconsistent training periods.

## 5. Core Use Cases

### 5.1 Track a planned workout

The user starts from a planned workout and records actual performance with minimal friction.

The app should make it easy to capture:

- completed sets;
- actual reps;
- actual weight;
- rest or timing information where relevant;
- RPE, RIR, or effort where relevant;
- skipped sets or exercises;
- substitutions;
- notes about pain, fatigue, equipment, or time;
- deviations from the plan.

The app should clearly distinguish between prescribed work and actual work.

Example:

Planned:

```text
Bench Press: 3 x 10 at 135
```

Actual:

```text
Set 1: 135 x 10
Set 2: 135 x 6
Set 3: skipped or adjusted
```

The user should not need to explain this in prose. The app should support it as a normal case.

### 5.2 Track an unplanned or modified workout

The user should be able to log a workout even when it was not planned in advance. The app should support quick capture without requiring the user to first create a perfect plan.

The user may start with:

- a blank workout;
- a previous workout;
- a rough template;
- a goal such as “upper body, 45 minutes”; or
- a coach-generated suggestion.

### 5.3 Adapt during a workout

If actual performance diverges from the plan, the app should be able to suggest adjustments for the remaining workout.

Examples:

- user misses prescribed reps;
- user exceeds prescribed reps;
- user reports pain;
- user has less time than expected;
- user changes available equipment;
- user feels unusually fatigued;
- user wants to push harder than planned.

Default behavior should be suggestion, not intrusive automation. The user should be able to accept, ignore, or override the adjustment.

### 5.4 Repair the plan after disruption

When the user misses workouts or stops training temporarily, the app should not shame, punish, or require manual cleanup.

The user should be able to return and ask, implicitly or explicitly:

> What should I do next?

The coach should decide the next useful workout based on current state, not blindly preserve the old calendar.

Default behavior:

- skip missed workouts unless there is a reason not to;
- repair the plan from the present;
- avoid making the user “catch up” by default;
- keep training moving.

### 5.5 Create a training plan

The user should be able to ask the app to create a plan using current goals, preferences, constraints, history, and training doctrine.

The plan may be oriented around:

- strength;
- hypertrophy;
- fat loss;
- conditioning;
- general fitness;
- functional strength;
- muscle gain;
- maintenance;
- return-to-training;
- time-efficient training;
- user-defined goals.

The app may provide presets, but presets should be starting points, not restrictive modes.

### 5.6 Adjust a training plan

The user should be able to change plan direction without rebuilding everything manually.

Examples:

- “Bias toward hypertrophy for the next 8 weeks.”
- “I want to focus on deadlift.”
- “I only have 3 days per week now.”
- “Make this better for fat loss.”
- “Reduce leg volume on weekdays.”
- “I want shorter sessions.”
- “Apply the principles from this document.”

The AI should have enough context to make the right change without repeatedly asking the user to restate goals or history.

### 5.7 Use uploaded training doctrine

The user should be able to provide content that guides the coach.

Examples:

- articles;
- program notes;
- personal training principles;
- notes from a human coach;
- methodology documents;
- rehab or constraint guidance;
- templates;
- book notes;
- prior plans.

The product should allow this content to influence planning. The user should be able to say, for example:

- “Use my 5/3/1 notes.”
- “Follow the principles from this hypertrophy document.”
- “Consider this rehab guidance when planning lower body work.”
- “Use this as my default conditioning approach.”

## 6. AI Product Requirements

### 6.1 AI role

AI should function as a planning and adaptation engine. It should not be positioned as a companion, social coach, motivational character, or general chatbot.

AI should help with:

- creating training plans;
- revising training plans;
- adapting today’s workout;
- adapting the next set or exercise when performance changes;
- repairing plans after missed workouts;
- interpreting recent workout history;
- applying user-defined coaching rules;
- applying uploaded training materials;
- explaining plan changes when asked;
- summarizing progress;
- converting workout data into useful Markdown;
- producing summaries for external systems.

### 6.2 AI interaction style

Default style should be dry, direct, and sparse.

The AI should ask questions only when it needs information that materially affects the plan or workout.

Good:

```text
Knee pain: sharp, dull, or general fatigue?
```

Bad:

```text
I’m sorry to hear that. Let’s work together to make sure your workout is safe and effective today.
```

The user should be able to make the coach more verbose, forgiving, motivational, technical, or chatty, but the default should be minimal.

### 6.3 AI context

For the AI to be useful without being chatty, it needs access to relevant context.

The coach should be able to use:

#### Current goals

- primary goal;
- secondary goals;
- active training emphasis;
- time horizon;
- constraints;
- goal changes over time.

#### Current plan

- active block or program;
- planned workouts;
- current week or phase;
- current session;
- intended progression;
- exercise targets;
- plan rules.

#### Recent workouts

- last completed workout;
- last several workouts;
- missed or skipped workouts;
- recent fatigue signals;
- recent pain notes;
- recent performance changes.

#### Long-term history

- exercise history;
- PRs;
- recurring sticking points;
- volume trends;
- frequency trends;
- exercises that work well;
- exercises that tend to cause problems;
- historical response to training styles.

#### User preferences

- preferred training style;
- liked exercises;
- disliked exercises;
- available equipment;
- usual session length;
- realistic schedule;
- intensity tolerance;
- preferred progression style;
- desired strictness;
- desired communication style.

#### Constraints

- injuries;
- pain patterns;
- recovery issues;
- time limits;
- equipment limits;
- schedule limits;
- movement restrictions;
- user-defined rules.

#### Training doctrine

- uploaded materials;
- named methodologies;
- user-written training principles;
- preset methods;
- coach instructions;
- documents the user wants the coach to consider.

#### Current workout state

- what has already been completed today;
- what remains in the workout;
- prescribed vs. actual performance;
- skipped or modified work;
- current fatigue;
- current pain notes;
- current time remaining;
- current user intent.

### 6.4 Coach configurability

The user should be able to define how the coach thinks and behaves.

Example coaching instructions:

```text
Prioritize consistency over intensity.
Use RPE when possible.
Bias toward hypertrophy for the next 8 weeks.
Avoid high-volume leg work on weekdays.
If I miss a session, do not make me catch up.
Prefer simple barbell movements.
Keep sessions under 45 minutes unless I explicitly say otherwise.
If performance drops sharply, reduce volume before increasing rest days.
Do not be motivational. Be concise.
```

The coach should be configurable at different levels:

- global default behavior;
- current goal or training block;
- specific methodology;
- specific workout type;
- temporary override.

### 6.5 AI authority

The AI should not alter factual completed workout logs. Completed logs should reflect what actually happened.

The AI may suggest or generate changes to:

- remaining work in today’s workout;
- future workouts;
- active training plan;
- goal emphasis;
- progression assumptions;
- exercise substitutions;
- recovery adjustments.

Default authority (settled, v0.2):

- completed workout data is factual and user-controlled — the coach never rewrites logged history;
- coach-generated plan changes **apply immediately by default** (no manual activation step);
- every applied change is **versioned and recoverable** — the user can inspect and restore an earlier plan version, and restoring is itself a normal versioned change;
- when the coach or user is explicitly weighing alternatives, the same mechanism can produce an **unapplied proposal** to preview before applying — a proposal is a candidate change to the same plan, not a separate system;
- today’s remaining workout can receive live adjustments;
- the user can override or restore past any plan decision.

## 7. Tracking Requirements

### 7.1 Structured tracking

The app should support rich structured tracking for common workout data:

- exercise;
- set;
- reps;
- weight;
- duration;
- distance;
- intensity;
- RPE/RIR;
- rest;
- tempo where useful;
- notes;
- prescribed target;
- actual result;
- completion state.

### 7.2 Flexible deviations

The app should make deviations first-class.

Supported cases should include:

- did fewer reps;
- did more reps;
- changed weight;
- skipped set;
- skipped exercise;
- substituted exercise;
- added extra set;
- changed rest;
- changed order;
- stopped early;
- reported pain;
- reported fatigue;
- changed goal mid-session;
- changed available time.

The app should not treat deviations as errors.

### 7.3 Planned vs. actual

The app should preserve both the intended plan and the actual result.

This matters because the planning engine needs to understand:

- whether the user complied with the plan;
- where the plan was too aggressive;
- where the user exceeded expectations;
- what changed during the workout;
- whether future training should adapt.

### 7.4 Minimal note burden

Notes should be available but not required. The product should avoid turning tracking into journaling homework.

Notes should be easy to attach to:

- a set;
- an exercise;
- a workout;
- a day;
- a plan;
- a goal;
- a constraint.

## 8. Planning Requirements

### 8.1 Planning horizon

The product should support flexible planning horizons:

- next workout;
- week;
- training block;
- goal-oriented period;
- ad hoc session.

The most important planning output is always:

> What should I do next?

Training blocks and weekly plans are useful, but the product should remain effective even when the user simply returns and wants the next useful session.

### 8.2 Plan adaptation

Plans should adapt based on:

- actual workout performance;
- missed workouts;
- changed goals;
- changed schedule;
- fatigue;
- pain;
- user preferences;
- uploaded training doctrine;
- long-term progress;
- user-defined coaching rules.

### 8.3 Plan repair

When a plan is disrupted, the product should repair forward from the current state.

The default should be:

- do not guilt the user;
- do not require manual rescheduling;
- do not force catch-up;
- do not restart unless useful;
- produce the next useful workout.

### 8.4 Presets

The app may provide built-in presets for common goals and training styles.

Examples:

- strength;
- hypertrophy;
- strength + hypertrophy;
- fat loss support;
- conditioning;
- general fitness;
- functional strength;
- return-to-training;
- low-time-commitment training.

Presets should be editable and steerable. The user should be able to override assumptions with personal instructions and uploaded context.

## 9. Markdown and Data Ownership Requirements

### 9.1 Markdown purpose

Markdown exists to make workout data:

- readable;
- durable;
- syncable;
- exportable;
- easy to inspect;
- useful to other tools;
- consumable by external AI systems;
- not locked into the app.

Markdown should not be exposed as the default input method for normal workout tracking.

### 9.2 Markdown quality

Generated Markdown should be clean enough to be useful outside the app.

It should preserve:

- plans;
- logs;
- goals;
- coach instructions;
- training notes;
- user preferences;
- uploaded doctrine references;
- summaries;
- reviews;
- deviations;
- prescribed vs. actual workout data.

### 9.3 External system compatibility

The user should be able to sync or feed workout Markdown into other systems, including personal AI workflows outside the app.

The product should support the idea that Workout.md is one part of a larger personal knowledge and automation system.

## 10. Training Coverage

The product should support multiple training domains.

V1 should understand:

- strength training;
- hypertrophy training;
- conditioning;
- cardio;
- general fitness;
- functional strength.

Strength and hypertrophy should be especially strong early domains, but the product model should not prevent other forms of training.

Users should be able to steer the app toward goals such as:

- fat loss;
- muscle gain;
- strength;
- hypertrophy;
- endurance;
- conditioning;
- mobility support;
- general health;
- functional capacity;
- sport support;
- maintenance.

## 11. ADHD/2e-Oriented Product Requirements

The product should not be branded as exclusively for ADHD or 2e users, but it should optimize for common failure modes relevant to those users.

Requirements:

- low setup burden;
- fast value on first use;
- no guilt or shame loops;
- no reliance on streak pressure;
- easy return after absence;
- plan repair after disruption;
- minimal decisions during workout;
- clear next action;
- ability to handle messy real-world behavior;
- ability to skip without breaking the system;
- ability to change goals without rebuilding everything;
- minimal notification burden;
- user should not need to maintain the app as a separate project.

The ideal posture:

> The user works out. The app absorbs mess.

## 12. Voice Requirements

Voice input is **part of v1** and first-class in onboarding, general coaching, and active
workouts. It is an input method that feeds the same text the keyboard feeds — the coach
receives text regardless of how it was captured, so voice never changes the coach's domain
model.

The product provides a transcription-provider abstraction: an Apple-native, on-device path
(the default where supported) and an optional ElevenLabs cloud path, with provider choice and
credentials in Settings. Recording shows visible state, supports long recordings and partial
transcripts where available, and always yields an **editable final transcript** the user
confirms before it is submitted to the coach. Voice remains optional — the product still works
excellently without it.

Potential voice uses:

- quick workout notes;
- hands-free set logging;
- asking for an adjustment during a workout;
- brief spoken confirmation;
- brief spoken plan summary.

Voice should not turn the product into a conversational assistant. The default product should still work excellently without voice.

The product should support both hosted and self-hosted voice options where feasible, consistent with the broader principle of user control and provider portability.

## 13. AI Provider and Local/Hosted Flexibility

The product should support the user’s preference for hosted or local AI where feasible.

High-level requirement:

- user should not be forced into a single proprietary AI provider;
- local or self-hosted options should be supported where practical;
- the app should remain useful even when AI features are unavailable or disabled;
- provider choice should not change the core product model.

This is a product requirement about user control and resilience, not a screen or implementation specification.

## 14. Non-Goals and Anti-Features

Workout.md should be:

- not social;
- not gamified;
- not streak-driven;
- not guilt-driven;
- not a chatbot;
- not a generic AI companion;
- not a proprietary data silo;
- not a Markdown textarea-first tracker;
- not a rigid template app;
- not a content-feed app;
- not a program marketplace-first product;
- not a system that asks the user to constantly maintain it;
- not a fitness influencer app;
- not an app that optimizes engagement over training outcomes.

The strongest anti-feature:

> The app should not make the user work for the app.

## 15. MVP Scope

### Must have

- Fast structured workout tracking.
- Planned vs. actual workout capture.
- Clean Markdown output.
- Basic plan creation.
- Basic plan adjustment.
- Ability to repair next workout after missed or modified sessions.
- User-configurable coach instructions.
- Current goals and preferences used by planning.
- Recent workout history used by planning.
- Support for strength and hypertrophy tracking.
- No social, streak, or gamified pressure.
- Coach-generated plan changes apply by default; versioned, recoverable plans.
- General durable coach memory (freeform coaching facts, not fixed categories).
- Conversational onboarding that produces a usable active plan.
- Voice input in onboarding, coaching, and active workouts (Apple-native default; ElevenLabs optional).
- Durable in-progress workouts that survive termination, with resume/discard on relaunch.

### Should have

- Conditioning and cardio support.
- Uploaded training doctrine influencing plans.
- In-session adjustment suggestions.
- Support for substitutions and skipped exercises.
- Summaries for external AI systems.
- Goal-oriented presets.
- Local/hosted AI provider flexibility.
- Optional concise explanations for plan changes.

### Could have later

- Spoken summaries.
- More advanced training-method presets.
- Deeper long-term trend analysis.
- Advanced plan review.
- External automation hooks.
- More sophisticated recovery modeling.
- Multiple coach policy profiles.

## 16. Success Criteria

The product is successful if:

- tracking a workout is faster than writing it manually;
- deviations are easy to capture;
- the user can miss workouts without breaking the plan;
- the next useful workout is usually obvious;
- AI reduces planning burden without becoming a chatbot;
- Markdown output is clean and useful outside the app;
- the user trusts the app to preserve factual workout history;
- the app does not require frequent maintenance;
- the user feels the app works for them, not the other way around.

## 17. Open Product Decisions

Settled (v0.2):

1. **How much can the coach automatically change in future plans without explicit approval?**
   — Settled: plan changes **apply by default** and are **versioned/recoverable**; the same
   mechanism offers an **optional unapplied proposal** when explicitly iterating. Completed
   history is never altered.
5. **Should voice be included in V1?** — Settled: **yes**, voice input is part of v1 (see §12, §19).

Still worth validating:

2. How aggressive should in-session adjustment be by default?
3. How much structure should be required for non-lifting workouts?
4. How prominent should uploaded training doctrine be in the initial product?
6. How much analytics is enough before the app starts feeling like a dashboard product?

## 18. Current Positioning Options

### Option A

> Fast workout tracking with a coach brain and Markdown memory.

### Option B

> A workout tracker that logs like an app, stores like Markdown, and plans like a coach.

### Option C

> A minimal-friction workout tracker with AI-assisted planning and user-owned Markdown data.

### Option D

> Workout.md helps you track what actually happened, adapt what comes next, and keep your training data yours.

## 19. Settled Product/Behavior Decisions (v0.2)

These are settled and implemented. They govern where earlier sections still read as open.

### 19.1 One canonical plan mechanism

There is one representation of a plan and one way to change it. Creating a plan, importing a
routine, building one collaboratively, editing a future workout, replacing an exercise during a
session, and restoring an earlier version are all the same mechanism: **composable structured
operations over stable identifiers**, applied to a plan (creating a plan is applying operations
to an empty plan). Related operations apply **atomically** (all-or-nothing). There are no
special-purpose plan tools (no separate "create onboarding plan", "swap exercise", "import
routine", "change schedule").

### 19.2 Apply by default, propose when useful

Coach-generated plan changes **apply immediately by default**. The same mechanism can instead
produce an **unapplied proposal** when the coach or user is explicitly weighing alternatives — a
proposal is a candidate change to the same plan model, previewed then applied or discarded, not a
second planning pipeline. Generated plans no longer wait for manual activation.

### 19.3 Versioned, recoverable plans

Every applied plan change creates recoverable history. The user can inspect and restore an earlier
version; restoring is itself a normal versioned change. A plan can express **more than one future
workout**, and the next workout is resolved by a simple cursor over the plan's sessions — **no
rigid calendar** — so missed sessions repair forward rather than forcing catch-up.

### 19.4 General durable memory

The coach has general primitives to add, update, query, and remove **freeform durable memories** —
any coaching-relevant fact (goals, equipment, schedule, injuries, preferences, disliked movements,
progression rules, …) with no mandatory categories. Memory is distinct from the conversation
transcript, uploaded reference/doctrine documents, the current plan and its revisions, active
workout state, and completed history. Every coach invocation — onboarding, planning, and live —
sees the current relevant memories.

### 19.5 A general coach

The coach operates with optional context: onboarding, general planning, Today, an active workout,
a specific exercise, or history review. It does not require a live workout or an exercise name
merely to have a conversation. Live-workout context is available when a workout exists but does not
own the coach.

### 19.6 Conversational onboarding

Onboarding is a coach conversation, not an intro-slide gate. A new user can describe their
situation, dictate an unstructured account, provide an existing routine, build a plan
collaboratively, or give minimal information and let the coach choose. The coach records memories
and normally creates and activates a usable plan directly. Onboarding is complete only when the
user has a usable active plan or explicitly chooses to continue without one — never merely because
screens were dismissed. There is no production dependency on a seeded starter plan (a sample plan
remains available as an explicit option).

### 19.7 Voice-first input

Covered in §12: voice is part of v1, first-class across onboarding/coaching/workouts, via a
transcription-provider abstraction (Apple-native default, ElevenLabs optional), always yielding an
editable final transcript. Provider choice never changes the coach's domain model.

### 19.8 Durable active workouts

An in-progress workout is persisted continuously (from the moment it starts, not at the end), so it
survives termination or a crash; on relaunch the user gets a clear resume-or-discard choice,
preserving position, completed/skipped sets, actual values, effort, substitutions, and session
transcript. Prescribed-vs-actual history is tracked by **stable identity**, so structural changes
during a live workout cannot corrupt the record of what was planned versus what happened.

### 19.9 Honest, recoverable data ownership

Markdown remains the first-class external format and stays clean and human-readable. Alongside the
human-readable body, plan and completed-session files carry a hidden **canonical block** that is
the restorable source of truth, so a fresh install or second device can reconstruct plans and
completed history from the sync source. Index/summary artifacts (e.g. the README) are explicitly
**export-only**, not restore sources. Completed-workout history is **factual and append-only** — it
is never destructively overwritten by external edits; external plan changes land as new plan
revisions.
