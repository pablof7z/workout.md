import Foundation
import Observation
import SwiftData

/// Owns the live `CoachEngine` (the Rust rig.rs agent, over UniFFI) and orchestrates one coach
/// turn end to end: reads Settings + Keychain to (re)configure the engine, builds the grounding
/// context and persisted-memory `history_json`, streams the reply into `WorkoutSession`'s
/// transcript, and routes tool calls to `WorkoutSession` so they actually mutate the runner's
/// upcoming sets.
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
    /// The tenex-edge fabric — same singleton `WorkoutMDApp` injects via `.environment`, so a turn's
    /// grounding context and any notable plan change it applies stay in sync with what `SettingsView`/
    /// `FabricView` show. See `send` (inbound context folded into grounding) and
    /// `WorkoutSessionCoachHost` (outbound notable-tool posts) below.
    private let fabric: FabricController

    /// Whether a turn is currently streaming, for a lightweight "thinking" affordance in `CoachView`.
    private(set) var isSending = false

    init(settings: AppSettings = .shared, engine: CoachEngine = CoachEngine(), fabric: FabricController = .shared) {
        self.settings = settings
        self.engine = engine
        self.fabric = fabric
        applySettings()
    }

    /// Re-applies the current provider/model/credentials to the engine. Cheap (just updates
    /// engine-held state, no network call) — called before every turn, and should also be called
    /// whenever `SettingsView` changes the provider, model, base URL, or stored key.
    func applySettings() {
        let apiKey = try? CoachSecrets.apiKey(for: settings.providerKind)
        engine.configureCoach(provider: settings.providerConfig(apiKey: apiKey), model: settings.model)
    }

    /// Sends the athlete's plain-language note for `exerciseName`, streaming the reply into
    /// `session`'s transcript (via `WorkoutSession.beginStreamingReply`/`appendStreamingDelta`/
    /// `finalizeStreamingReply`) and applying any tool call the model makes directly to `session`.
    /// Every new turn (the athlete's note, the coach's reply, and each applied-diff line) is
    /// persisted to `CoachNoteRecord` (`workout == nil` — a standalone, not-yet-session-attached
    /// note), which is what `historyJSON(for:modelContext:)` reads back to give the coach memory
    /// across turns and app launches.
    func send(userMessage: String, exerciseName: String, session: WorkoutSession, modelContext: ModelContext) {
        let text = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        applySettings()

        let planID = session.activePlan?.id

        // Build history from whatever was persisted BEFORE this turn — otherwise the note we're
        // about to persist below would double up as both `history_json` and `user_message`. Scoped to
        // the current plan (p2) so "Bench Press" memory from a plan the athlete finished months ago
        // doesn't bleed into the current one.
        let historyJson = Self.historyJSON(for: exerciseName, planID: planID, modelContext: modelContext)

        session.appendUserMessage(text, to: exerciseName)
        Self.persistNote(kind: .user, text: text, exercise: exerciseName, planID: planID, modelContext: modelContext)

        let grounding = session.coachContext(for: exerciseName)
        // M4: fold in the athlete's configured goal/session length/dislikes so the Settings claim
        // ("the coach sees these as grounding") is actually true, plus (M7) a digest of any uploaded
        // training doctrine, plus (M2) recent reviews of external Markdown changes — each empty (and
        // cheap) when there's nothing to add.
        let goalsContext = settings.goalsContextSnippet
        let doctrineContext = settings.doctrineEnabled ? DoctrineStore.shared.digest() : ""
        let reviewContext = CoachReviewStore.shared.contextSnippet()
        // Folds in recent tenex-edge fabric traffic (from the user's other agents) so the coach is
        // aware of it — e.g. it can note "there are new messages from your assistant" and factor them
        // in — before the athlete's own note. Empty (and a no-op `contextSnippet` call) when the
        // fabric is disabled or nothing new has arrived.
        let fabricContext = fabric.contextSnippet()

        let contextBlocks = [grounding, goalsContext, doctrineContext, reviewContext, fabricContext]
            .filter { !$0.isEmpty }
        let combinedUserMessage = (contextBlocks + ["Athlete note: \(text)"]).joined(separator: "\n\n")

        isSending = true
        session.beginStreamingReply(for: exerciseName)

        let sink = CoachStreamSink(
            session: session,
            exerciseName: exerciseName,
            onCompleted: { [weak self] fullText in
                self?.isSending = false
                let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Self.persistNote(kind: .coach, text: fullText, exercise: exerciseName, planID: planID, modelContext: modelContext)
            },
            onError: { [weak self] _ in
                self?.isSending = false
            }
        )

        let host = WorkoutSessionCoachHost(session: session, exerciseName: exerciseName, fabric: fabric) { confirmation in
            Self.persistNote(kind: .diff, text: confirmation, exercise: exerciseName, planID: planID, modelContext: modelContext)
        }

        engine.sendMessage(
            systemPrompt: settings.effectiveSystemPrompt,
            userMessage: combinedUserMessage,
            historyJson: historyJson,
            sink: sink,
            host: host
        )
    }

    // MARK: - Plan generation ("create_plan" / "propose_plan")

    /// Generates a plan proposal from a free-text goal (e.g. "upper body, 45 min, hypertrophy") or,
    /// for the Today "What should I do next?" repair flow, a richer prompt built from recent
    /// session history. Implemented as one dedicated, non-conversational coach turn that asks for a
    /// structured JSON reply and parses it (see `PlanGeneration.swift`) — the simpler, robust path
    /// the product spec allows instead of a new Rust-core tool + bindings regen. `completion` is
    /// always called on the main thread.
    func generatePlan(goalPrompt: String, sessionLengthMinutes: Int, completion: @escaping (Result<PlanRecord, PlanGenerationError>) -> Void) {
        applySettings()

        let userMessage = """
        Goal: \(goalPrompt)
        Target session length: \(sessionLengthMinutes) minutes.

        Reply with ONLY the JSON object described in your instructions — no prose, no markdown code fence, nothing before or after the braces.
        """

        isSending = true
        let sink = PlanGenerationSink(
            onCompleted: { [weak self] fullText in
                self?.isSending = false
                guard let proposal = ProposedPlan.parse(fullText) else {
                    completion(.failure(.malformedResponse(fullText)))
                    return
                }
                completion(.success(proposal.makePlanRecord()))
            },
            onError: { [weak self] message in
                self?.isSending = false
                completion(.failure(.engineError(message)))
            }
        )

        engine.sendMessage(
            systemPrompt: Self.planGenerationSystemPrompt,
            userMessage: userMessage,
            historyJson: "[]",
            sink: sink,
            host: NoopCoachHost()
        )
    }

    private static let planGenerationSystemPrompt = """
    You are a strength coach designing a workout plan. Given the athlete's goal and target session \
    length, respond with ONLY a single JSON object — no markdown code fences, no prose before or \
    after — of exactly this shape:
    {"name": string, "goal": string, "blocks": [{"kind": "straight"|"superset"|"circuit", "label": \
    string, "rounds": integer, "restSeconds": integer or null, "exercises": [{"name": string, \
    "cue": string, "sets": [{"reps": integer or null, "weight": number or null, "seconds": integer \
    or null}]}]}]}
    Rules: a "straight" block has exactly one exercise; "superset"/"circuit" blocks have two or more \
    exercises sharing "rounds", and each exercise's "sets" array should have exactly one entry per \
    round. Use "seconds" (and leave "reps"/"weight" null) for a timed hold; otherwise use "reps" \
    (and "weight" if it's a loaded movement, null for bodyweight). Keep the plan realistic for the \
    stated session length and goal. Never include commentary outside the JSON object.
    """

    // MARK: - External-commit review (M2)

    /// Wired from `SyncManager`'s singleton init to `GitHubSync.onExternalChanges` — fires whenever
    /// `GitHubSync.pull()` finds commits the app didn't author itself (someone edited a session's
    /// Markdown on github.com, or pushed from a laptop). `pull()` already ingests the changed file
    /// content; this is what actually has the coach *look* at it and produce a terse review note,
    /// finishing the goal's "the agent reviews new commits" promise (previously only half-built).
    ///
    /// One dedicated, non-conversational turn (same shape as `generatePlan`) rather than something
    /// attached to a live `WorkoutSession`'s transcript — a sync pull can happen with no session open
    /// at all. The resulting note is appended to `CoachReviewStore`, which both makes it visible to a
    /// "coach reviewed your changes" surface and folds it into every subsequent `send()`'s grounding.
    func reviewExternalChanges(_ changes: [GitHubSync.ChangedFile]) {
        guard !changes.isEmpty else { return }
        applySettings()

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

        let sink = PlanGenerationSink(
            onCompleted: { fullText in
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

        engine.sendMessage(
            systemPrompt: settings.effectiveSystemPrompt,
            userMessage: userMessage,
            historyJson: "[]",
            sink: sink,
            host: NoopCoachHost()
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

/// Marshals every `CoachSink` callback onto the main thread before touching `WorkoutSession`. No
/// synchronous return value is needed here (unlike `CoachHost.applyTool` below), so a plain async
/// hop is enough — `@unchecked Sendable` is safe because every actual field access happens only
/// after landing on the main thread.
private final class CoachStreamSink: CoachSink, @unchecked Sendable {
    private let session: WorkoutSession
    private let exerciseName: String
    private let onCompleted: (String) -> Void
    private let onError: (String) -> Void

    init(session: WorkoutSession, exerciseName: String, onCompleted: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.session = session
        self.exerciseName = exerciseName
        self.onCompleted = onCompleted
        self.onError = onError
    }

    func onTextDelta(delta: String) {
        DispatchQueue.main.async { [session, exerciseName] in
            session.appendStreamingDelta(delta, exercise: exerciseName)
        }
    }

    /// Display-only notification per the Rust doc comment — the actual mutation (and the
    /// confirmation string worth showing) happens in `WorkoutSessionCoachHost.applyTool`, which is
    /// the one that knows the outcome. Nothing to do here.
    func onToolCall(name: String, argsJson: String) {}

    func onCompleted(fullText: String) {
        DispatchQueue.main.async { [session, exerciseName, onCompleted] in
            session.finalizeStreamingReply(for: exerciseName, fullText: fullText)
            onCompleted(fullText)
        }
    }

    func onError(message: String) {
        DispatchQueue.main.async { [session, exerciseName, onError] in
            session.finalizeStreamingReply(for: exerciseName, replaceWithError: message)
            onError(message)
        }
    }
}

// MARK: - CoachHost

/// Executes each coach tool call against the shared `WorkoutSession` and reports the resulting
/// confirmation for persistence. Called from the coach engine's background tokio thread — every
/// mutation is marshaled onto the main thread via `DispatchQueue.main.sync`, which blocks only that
/// background thread (not the UI) until the main-thread work — and the string it produces — is
/// done, satisfying `CoachHost.applyTool`'s synchronous, value-returning contract.
private final class WorkoutSessionCoachHost: CoachHost, @unchecked Sendable {
    private let session: WorkoutSession
    private let exerciseName: String
    private let fabric: FabricController
    private let onApplied: (String) -> Void

    /// Tool names whose confirmation is a genuine plan change (not just a freestanding note) — worth
    /// a terse fabric post so the user's other agents see it land, per the product vision ("dropped
    /// bench to 125 after back tweak"). `add_note`/`edit_plan` are left out: they're not concrete
    /// numeric changes to the plan the fabric needs to know about turn by turn.
    private static let notableTools: Set<String> = ["adjust_set", "skip_set", "deload_exercise"]

    init(session: WorkoutSession, exerciseName: String, fabric: FabricController, onApplied: @escaping (String) -> Void) {
        self.session = session
        self.exerciseName = exerciseName
        self.fabric = fabric
        self.onApplied = onApplied
    }

    func applyTool(name: String, argsJson: String) -> String {
        DispatchQueue.main.sync { [session, exerciseName, fabric, onApplied] in
            let confirmation = session.applyCoachTool(name: name, argsJson: argsJson, transcriptExercise: exerciseName)
            onApplied(confirmation)
            if Self.notableTools.contains(name) {
                fabric.postSummary("\(exerciseName): \(confirmation)")
            }
            return confirmation
        }
    }
}
