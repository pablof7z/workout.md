import Foundation
import Observation
import SwiftData

/// The general coach modes a turn can be sent under — used by `CoachContextAssembler` to decide
/// which context blocks are worth including, and by `systemPromptAugmentation` below to give the
/// turn a clear job. See `docs/architecture/domain-primitives.md` §6. Unlike the old design, a mode
/// no longer picks a model tier — every mode starts on `CoachModelTier.fast`, and the coach itself
/// escalates to `.reasoning` mid-turn (via the `escalate_to_reasoning` tool) when a task demands it,
/// regardless of which mode it's running under.
enum CoachMode {
    case onboarding
    case planning
    case today
    case activeWorkout
    case exercise
    case historyReview

    /// Layered on top of `AppSettings.effectiveSystemPrompt` in `CoachController.converse` — the
    /// generic coach voice alone never actually told onboarding to gather goals and build a plan, so
    /// it just sat there waiting on the athlete instead of driving the conversation. Empty for modes
    /// that already have a clear job from their surrounding context (`.activeWorkout`/`.exercise`'s
    /// per-exercise grounding, `.historyReview`'s own inline instructions).
    var systemPromptAugmentation: String {
        switch self {
        case .onboarding:
            return "\n\n" +
                "You are onboarding a NEW athlete who has no plan yet. In this conversation: (1) learn only " +
                "what you need — training goal, experience level, available equipment, weekly schedule / " +
                "session length, and any injuries or strong preferences — asking at most one or two concise " +
                "questions at a time and ONLY for materially missing info; (2) record durable facts as you " +
                "learn them via memory_add; (3) as soon as you have enough (or the athlete says \"you choose\"), " +
                "CREATE and ACTIVATE a concrete starting plan by calling plan_apply — build real sessions/" +
                "blocks/exercises/sets from what they told you; do NOT wait for permission and do NOT use any " +
                "canned template. Prefer building over interrogating. After creating it, tell them it's ready " +
                "and that they can change anything. Keep replies short."
        case .planning:
            return "\n\n" +
                "Build a NEW plan proposal from the athlete's request. Start from the plan returned by " +
                "plan_get; if it says there is no active plan, construct real sessions/blocks/exercises/sets " +
                "and call plan_apply. Do not edit, copy, or rely on the athlete's currently saved plan unless " +
                "they explicitly ask you to. plan_apply only updates the on-screen draft in this mode; the " +
                "athlete decides whether to save it. If they ask for a revision after you made a proposal, call " +
                "plan_get for the draft's stable IDs and apply the requested changes. Never print or summarize " +
                "raw JSON. Keep the conversational reply short because the full proposal is visible on screen."
        case .today:
            return "\n\n" +
                "Propose the athlete's next session by calling plan_apply, rather than only describing it."
        case .activeWorkout, .exercise, .historyReview:
            return ""
        }
    }
}

/// Owns the live `CoachEngine` (the Rust rig.rs agent, over UniFFI) and orchestrates coach turns
/// end to end — the app-level entry point is `converse(mode:userText:...)`, which works with or
/// without a live `WorkoutSession` (domain-primitives.md §6): it reads Settings + Keychain to
/// (re)configure the engine, assembles the bounded context via `CoachContextAssembler`, streams the
/// reply through `ThinkStripper`, and dispatches tool calls to `AppCoachHost` (which routes to
/// `PlanRepository`/`MemoryStore`/the live session). `send(userMessage:exerciseName:session:
/// modelContext:)` is a thin wrapper over `converse` that wires its callbacks to
/// `WorkoutSession`'s transcript, preserving the in-session coach flow `CoachView` drives.
///
/// Created once at the app root (`WorkoutMDApp`) and injected via `.environment(CoachController.self)`
/// so both `CoachView` and `SettingsView` share the same engine instance.
///
/// ## Threading
/// `CoachSink`/`CoachHost` callbacks are invoked by the Rust core from its own background tokio
/// runtime — never from the thread that called `send_message`. `CoachSink`'s methods return `Void`,
/// so they're marshaled onto the main thread with a simple `DispatchQueue.main.async` hop before
/// touching `WorkoutSession`/SwiftData. `CoachHost.applyTool`, however, must hand the model's tool
/// call a *return value* — the confirmation string it sees as the tool result — so that hop has to
/// be synchronous: `DispatchQueue.main.sync` blocks only the calling background thread until the
/// main-thread mutation (and its resulting string) is ready, never the UI thread itself.
@Observable
final class CoachController {
    /// A second, independent `CoachController` for turns that don't belong to any live
    /// `WorkoutSession` — today just `reviewExternalChanges(_:)` (M2), called from `SyncManager`'s
    /// singleton init, which has no session/transcript to attach a turn to. Deliberately NOT the same
    /// instance `WorkoutMDApp`'s `RootView` builds for the UI (that one is still constructed with a
    /// plain `CoachController()` there) — the two never share transcript/streaming state, only the
    /// same `AppSettings`/`FabricController` singletons, which is all a background review turn needs.
    static let shared = CoachController()

    private let engine: CoachEngine
    private let settings: AppSettings
    private let appleIntelligence: AppleIntelligenceCoachProvider
    /// The tenex-edge fabric — same singleton `WorkoutMDApp` injects via `.environment`, so a turn's
    /// grounding context and any notable plan change it applies stay in sync with what `SettingsView`/
    /// `FabricView` show. See `CoachContextAssembler` (inbound context folded into grounding) and
    /// `AppCoachHost` (outbound notable-tool posts).
    private let fabric: FabricController

    /// Whether a turn is currently streaming, for a lightweight "thinking" affordance in `CoachView`.
    /// Stays `true` across an escalation re-run (see `converse`'s `forceTier`) — only the final turn
    /// clears it.
    private(set) var isSending = false

    /// Set by the current turn's `AppCoachHost.onEscalate` closure when the model calls
    /// `escalate_to_reasoning`. Reset to `false` at the start of every FRESH (non-escalated) turn in
    /// `converse`, then consulted once that turn's sink completes to decide whether to re-run it on
    /// `.reasoning` instead of forwarding the fast turn's own (likely near-empty) reply. A plain
    /// instance property is safe here — `AppCoachHost.applyTool` already hops onto the main thread
    /// before touching anything, and so does the sink completion below.
    private var escalationRequested = false

    init(
        settings: AppSettings = .shared,
        engine: CoachEngine = CoachEngine(),
        fabric: FabricController = .shared,
        appleIntelligence: AppleIntelligenceCoachProvider = AppleIntelligenceCoachProvider()
    ) {
        self.settings = settings
        self.engine = engine
        self.fabric = fabric
        self.appleIntelligence = appleIntelligence
        applySettings()
    }

    /// Re-applies the current provider/model/credentials to the engine. Cheap (just updates
    /// engine-held state, no network call) — called before every turn, and should also be called
    /// whenever `SettingsView` changes the provider, the fast-tier model, the base URL, or a stored
    /// key. (Changing the reasoning-tier model alone needs no such call — it only takes effect the
    /// next time the coach escalates.)
    func applySettings(tier: CoachModelTier = .fast) {
        guard settings.providerKind != .appleIntelligence else { return }
        let apiKey = try? CoachSecrets.apiKey(for: settings.providerKind)
        guard let provider = settings.providerConfig(apiKey: apiKey) else { return }
        engine.configureCoach(provider: provider, model: settings.model(for: tier))
    }

    /// The app-level entry point (domain-primitives.md §6): assembles the bounded context via
    /// `CoachContextAssembler`, configures the engine for the current tier, builds an `AppCoachHost`
    /// scoped to `session`/`focusExercise` (both optional — the coach works with or without a live
    /// workout), and drives one turn. `CoachConverseSink` runs every delta and the final text
    /// through `ThinkStripper` first, so reasoning-model `<think>`/`<thinking>` blocks never reach a
    /// caller's `onDelta`/`onComplete`. Callers own persistence/transcript wiring via the closures —
    /// `converse` itself has no `WorkoutSession`-specific side effects, which is what lets `send`
    /// below stay a thin wrapper and lets onboarding/planning/history-review turns call this with no
    /// session at all.
    ///
    /// ## Escalation
    /// Every turn starts on `forceTier == nil`, i.e. `CoachModelTier.fast`. If the model calls
    /// `escalate_to_reasoning` (routed here via `AppCoachHost.onEscalate`), the sink's completion
    /// below does NOT forward that fast turn's `onComplete` — instead it immediately re-invokes
    /// `converse` with the SAME `userText`/callbacks and `forceTier: .reasoning`. Every caller's
    /// `onDelta` replaces the streaming text wholesale rather than appending
    /// (`CoachConversationView.replaceStreamingText`/`WorkoutSession.replaceStreamingText`), so the
    /// reasoning turn's stream cleanly overwrites whatever brief routing text the fast turn produced
    /// before calling the tool. A `forceTier`d (reasoning) turn never re-escalates — see the guard
    /// below — and its `onComplete` is always forwarded normally. If escalation was requested but no
    /// distinct reasoning model is configured (`AppSettings.model(for:.reasoning)` falls back to
    /// fast in that case), escalation is a no-op and the fast turn's own reply is forwarded as-is.
    func converse(
        mode: CoachMode,
        userText: String,
        modelContext: ModelContext,
        session: WorkoutSession? = nil,
        focusExercise: String? = nil,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onDiff: @escaping (String) -> Void = { _ in },
        planProposal: PlanSnapshot? = nil,
        onPlanProposal: @escaping (PlanSnapshot) -> Void = { _ in }
    ) {
        runTurn(
            mode: mode, userText: userText, modelContext: modelContext, session: session, focusExercise: focusExercise,
            onDelta: onDelta, onComplete: onComplete, onError: onError, onDiff: onDiff,
            planProposal: planProposal, onPlanProposal: onPlanProposal, forceTier: nil
        )
    }

    /// Does the actual work for `converse` — split out so `forceTier` (the escalation re-run switch)
    /// stays a private implementation detail no caller outside this file can pass; every external
    /// caller only ever sees `converse`'s public signature, which always starts a turn at
    /// `forceTier == nil`.
    private func runTurn(
        mode: CoachMode,
        userText: String,
        modelContext: ModelContext,
        session: WorkoutSession?,
        focusExercise: String?,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void,
        onDiff: @escaping (String) -> Void,
        planProposal: PlanSnapshot?,
        onPlanProposal: @escaping (PlanSnapshot) -> Void,
        forceTier: CoachModelTier?
    ) {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let tier = forceTier ?? .fast
        applySettings(tier: tier)
        if forceTier == nil {
            escalationRequested = false
        }

        // Reuses the persisted-note history, scoped to whatever exercise/plan the turn is about
        // (p2) so memory from a long-finished plan doesn't bleed into the current one; a turn with
        // no `focusExercise` (onboarding/planning/review) has no exercise-scoped transcript to draw
        // on, so it starts from an empty history.
        let historyJson: String
        if let focusExercise {
            let planID = session?.activePlan?.id ?? PlanRepository(context: modelContext).activeSnapshot()?.id
            historyJson = Self.historyJSON(for: focusExercise, planID: planID, modelContext: modelContext)
        } else {
            historyJson = "[]"
        }

        let contextBlock = CoachContextAssembler.build(
            mode: mode, session: session, focusExercise: focusExercise,
            modelContext: modelContext, settings: settings, fabric: fabric
        )
        let combinedUserMessage = contextBlock.isEmpty ? "Athlete note: \(text)" : "\(contextBlock)\n\nAthlete note: \(text)"

        isSending = true
        let proposalBehavior: AppCoachHost.PlanToolBehavior = mode == .planning
            ? .buildProposal(planProposal) : .applyImmediately
        let host = AppCoachHost(
            modelContext: modelContext, session: session, focusExercise: focusExercise, fabric: fabric,
            planToolBehavior: proposalBehavior, onPlanProposal: onPlanProposal, onDiff: onDiff,
            onEscalate: { [weak self] in self?.escalationRequested = true }
        )

        if settings.providerKind == .appleIntelligence {
            appleIntelligence.send(
                mode: mode,
                systemPrompt: settings.effectiveSystemPrompt + mode.systemPromptAugmentation,
                userMessage: combinedUserMessage,
                historyJSON: historyJson,
                host: host,
                hasLiveSession: session != nil,
                onDelta: { visible in onDelta(ThinkStripper.strip(visible)) },
                onComplete: { [weak self] fullText in
                    self?.isSending = false
                    onComplete(ThinkStripper.strip(fullText))
                },
                onError: { [weak self] message in
                    self?.isSending = false
                    onError(message)
                }
            )
            return
        }

        let sink = CoachConverseSink(
            onDelta: onDelta,
            onCompleted: { [weak self] fullText in
                guard let self else {
                    onComplete(fullText)
                    return
                }
                let reasoningModel = self.settings.model(for: .reasoning)
                let canEscalate = forceTier == nil && self.escalationRequested
                    && !reasoningModel.isEmpty && reasoningModel != self.settings.model(for: .fast)
                guard canEscalate else {
                    self.isSending = false
                    onComplete(fullText)
                    return
                }
                self.runTurn(
                    mode: mode, userText: userText, modelContext: modelContext,
                    session: session, focusExercise: focusExercise,
                    onDelta: onDelta, onComplete: onComplete, onError: onError, onDiff: onDiff,
                    planProposal: planProposal, onPlanProposal: onPlanProposal,
                    forceTier: .reasoning
                )
            },
            onError: { [weak self] message in
                self?.isSending = false
                onError(message)
            }
        )

        engine.sendMessage(
            systemPrompt: settings.effectiveSystemPrompt + mode.systemPromptAugmentation,
            userMessage: combinedUserMessage,
            historyJson: historyJson,
            sink: sink,
            host: host
        )
    }

    /// Sends the athlete's plain-language note for `exerciseName` against a live `session` — the
    /// in-session coach flow `CoachView` drives, kept behavior-identical by wiring `converse`'s
    /// generic callbacks straight to `WorkoutSession`'s existing streaming-transcript methods
    /// (`beginStreamingReply`/`replaceStreamingText`/`finalizeStreamingReply`) and persisting every
    /// new turn (the athlete's note, the coach's reply, and each applied-diff line) to
    /// `CoachNoteRecord` (`workout == nil` — a standalone, not-yet-session-attached note), which is
    /// what `historyJSON(for:modelContext:)` reads back to give the coach memory across turns and
    /// app launches. The user's own note is persisted AFTER `converse` computes `history_json`, not
    /// before, so this turn's own note never double-counts as both history and the live message.
    func send(userMessage: String, exerciseName: String, session: WorkoutSession, modelContext: ModelContext) {
        let text = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let planID = session.activePlan?.id
        session.appendUserMessage(text, to: exerciseName)
        session.beginStreamingReply(for: exerciseName)

        converse(
            mode: .activeWorkout,
            userText: text,
            modelContext: modelContext,
            session: session,
            focusExercise: exerciseName,
            onDelta: { [weak session] visible in
                session?.replaceStreamingText(visible, for: exerciseName)
            },
            onComplete: { [weak session] visible in
                session?.finalizeStreamingReply(for: exerciseName, fullText: visible)
                guard !visible.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Self.persistNote(kind: .coach, text: visible, exercise: exerciseName, planID: planID, modelContext: modelContext)
            },
            onError: { [weak session] message in
                session?.finalizeStreamingReply(for: exerciseName, replaceWithError: message)
            },
            onDiff: { confirmation in
                Self.persistNote(kind: .diff, text: confirmation, exercise: exerciseName, planID: planID, modelContext: modelContext)
            }
        )

        Self.persistNote(kind: .user, text: text, exercise: exerciseName, planID: planID, modelContext: modelContext)
    }

    // MARK: - External-commit review (M2)

    /// Wired from `SyncManager`'s singleton init to `GitHubSync.onExternalChanges` — fires whenever
    /// `GitHubSync.pull()` finds commits the app didn't author itself (someone edited a session's
    /// Markdown on github.com, or pushed from a laptop). `pull()` already ingests the changed file
    /// content; this is what actually has the coach *look* at it and produce a terse review note,
    /// finishing the goal's "the agent reviews new commits" promise (previously only half-built).
    ///
    /// Routed through the general `converse(mode: .historyReview, ...)` turn (slice 8 — previously a
    /// dedicated non-conversational turn built on `PlanGenerationSink`, the same bespoke-pipeline
    /// mechanism `generatePlan` used, since removed per domain-primitives.md invariants 1/2). This
    /// is called from `SyncManager`'s singleton init, which has no SwiftUI environment (hence no
    /// `ModelContext` in scope) — a fresh `ModelContext` is opened against the shared container the
    /// same way `SyncManager.ingestCanonicalChanges` does, rather than requiring a caller-supplied
    /// one. The resulting note is appended to `CoachReviewStore`, which both makes it visible to a
    /// "coach reviewed your changes" surface and folds it into every subsequent turn's grounding.
    func reviewExternalChanges(_ changes: [GitHubSync.ChangedFile]) {
        guard !changes.isEmpty else { return }

        let digest = changes.prefix(5).map { file -> String in
            "### \(file.path) (commit: \(file.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)))\n\(file.content.prefix(1500))"
        }.joined(separator: "\n\n")

        let userMessage = """
        The athlete (or someone else) just edited their training Markdown outside the app — these \
        changes were pulled from the synced GitHub repo, not made by the app itself. Review what \
        changed and reply with ONE terse sentence, in your normal dry coach voice, noting what you \
        saw and how — if at all — it changes your approach going forward. No prose beyond that one \
        sentence, no markdown, no bullet points, no preamble.

        Changed file(s):
        \(digest)
        """

        let context = ModelContext(WorkoutMDApp.sharedModelContainer)
        converse(
            mode: .historyReview,
            userText: userMessage,
            modelContext: context,
            onDelta: { _ in },
            onComplete: { fullText in
                let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                CoachReviewStore.shared.append(CoachReviewNote(
                    changedPaths: changes.map(\.path),
                    commitMessage: changes.first?.commitMessage ?? "",
                    note: trimmed
                ))
            },
            onError: { _ in
                // A failed review turn (offline model, bad config, ...) shouldn't surface as an app
                // error — the sync pull itself already succeeded; the review is a best-effort extra.
            }
        )
    }

    // MARK: - Persisted memory

    /// Reads back up to `limit` persisted `CoachNoteRecord`s scoped to `exercise` (oldest first,
    /// regardless of whether they're standalone or already bridged into a finished
    /// `WorkoutRecord`), maps them to the `{"role", "content"}` shape `send_message` expects, and
    /// encodes them as JSON. This is the coach's actual cross-launch memory: a fresh app launch,
    /// with no in-memory `WorkoutSession` transcript yet, still recalls what was said/applied last
    /// time this exercise came up.
    ///
    /// (p2) Scoped two ways so memory stays coherent rather than bleeding a bare exercise name across
    /// every plan/era the athlete has ever trained under: **plan** — only notes said under `planID`
    /// (or with no plan recorded at all, e.g. notes persisted before this field existed) are eligible
    /// — and **recency** — only the last `recencyWindowDays` days, so a stale note from a
    /// long-abandoned run of the same plan doesn't keep echoing forever.
    private static func historyJSON(
        for exercise: String,
        planID: UUID?,
        modelContext: ModelContext,
        limit: Int = 24,
        recencyWindowDays: Int = 60
    ) -> String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -recencyWindowDays, to: .now) ?? .distantPast
        var descriptor = FetchDescriptor<CoachNoteRecord>(
            predicate: #Predicate { $0.exerciseName == exercise && $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descriptor.fetchLimit = 500 // generous cap before the plan filter + trailing window below
        guard let fetched = try? modelContext.fetch(descriptor) else { return "[]" }

        // Plan filter done in Swift (rather than folded into the predicate above) to keep the
        // `note.planID == nil || note.planID == planID` optional-equality logic simple and obviously
        // correct rather than fighting `#Predicate`'s macro expressiveness over `Optional<UUID>`.
        let scoped = fetched.filter { $0.planID == nil || $0.planID == planID }

        let entries = scoped.suffix(limit).map { note -> [String: String] in
            let role = (note.kind == .user) ? "user" : "assistant"
            return ["role": role, "content": note.text]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func persistNote(kind: RecordCoachKind, text: String, exercise: String, planID: UUID? = nil, modelContext: ModelContext) {
        guard !text.isEmpty else { return }
        let note = CoachNoteRecord(order: 0, kind: kind, text: text, exerciseName: exercise, date: .now, planID: planID)
        modelContext.insert(note)
        try? modelContext.save()
    }
}

// MARK: - CoachSink

/// Marshals every `CoachSink` callback onto the main thread before invoking `converse`'s
/// `onDelta`/`onCompleted`/`onError` closures — the generic counterpart of the old
/// session-specific `CoachStreamSink`, now with no `WorkoutSession` dependency of its own (callers
/// supply whatever side effect they need via the closures; see `CoachController.send`). No
/// synchronous return value is needed here (unlike `CoachHost.applyTool`, which `AppCoachHost`
/// implements), so a plain async hop is enough — `@unchecked Sendable` is safe because every actual
/// closure invocation happens only after landing on the main thread.
private final class CoachConverseSink: CoachSink, @unchecked Sendable {
    private let onDelta: (String) -> Void
    private let onCompleted: (String) -> Void
    private let onError: (String) -> Void

    /// Accumulates raw `on_text_delta` chunks and exposes the think-stripped "visible" projection —
    /// see `ThinkStripper`. `CoachSink` callbacks for a single turn are delivered serially off one
    /// background tokio task, so mutating this here (before hopping to main) is safe without extra
    /// locking.
    private var thinkBuffer = ThinkStripper.Buffer()

    init(onDelta: @escaping (String) -> Void, onCompleted: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onDelta = onDelta
        self.onCompleted = onCompleted
        self.onError = onError
    }

    func onTextDelta(delta: String) {
        // `visible` can both grow and *shrink* relative to the last delta (a model that omits the
        // opening `<think>` tag makes everything before an eventual orphan `</think>` retroactively
        // hidden), so callers are handed the whole visible text each time, not just an appended
        // fragment.
        let visible = thinkBuffer.append(delta)
        DispatchQueue.main.async { [onDelta] in onDelta(visible) }
    }

    /// Display-only notification per the Rust doc comment — the actual mutation (and the
    /// confirmation string worth showing) happens in `AppCoachHost.applyTool`, which is the one that
    /// knows the outcome. Nothing to do here.
    func onToolCall(name: String, argsJson: String) {}

    func onCompleted(fullText: String) {
        // The model's authoritative full text can still contain think blocks even after streaming
        // deltas were stripped for display (e.g. a turn that only ever sent one big `on_completed`
        // with no intervening deltas) — strip it too, so both the caller's transcript and anything
        // it persists are the visible text.
        let visible = ThinkStripper.strip(fullText)
        DispatchQueue.main.async { [onCompleted] in onCompleted(visible) }
    }

    func onError(message: String) {
        DispatchQueue.main.async { [onError] in onError(message) }
    }
}
