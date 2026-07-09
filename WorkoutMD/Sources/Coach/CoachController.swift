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
    private let engine: CoachEngine
    private let settings: AppSettings

    /// Whether a turn is currently streaming, for a lightweight "thinking" affordance in `CoachView`.
    private(set) var isSending = false

    init(settings: AppSettings = .shared, engine: CoachEngine = CoachEngine()) {
        self.settings = settings
        self.engine = engine
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

        // Build history from whatever was persisted BEFORE this turn — otherwise the note we're
        // about to persist below would double up as both `history_json` and `user_message`.
        let historyJson = Self.historyJSON(for: exerciseName, modelContext: modelContext)

        session.appendUserMessage(text, to: exerciseName)
        Self.persistNote(kind: .user, text: text, exercise: exerciseName, modelContext: modelContext)

        let grounding = session.coachContext(for: exerciseName)
        let combinedUserMessage = "\(grounding)\n\nAthlete note: \(text)"

        isSending = true
        session.beginStreamingReply(for: exerciseName)

        let sink = CoachStreamSink(
            session: session,
            exerciseName: exerciseName,
            onCompleted: { [weak self] fullText in
                self?.isSending = false
                let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Self.persistNote(kind: .coach, text: fullText, exercise: exerciseName, modelContext: modelContext)
            },
            onError: { [weak self] _ in
                self?.isSending = false
            }
        )

        let host = WorkoutSessionCoachHost(session: session, exerciseName: exerciseName) { confirmation in
            Self.persistNote(kind: .diff, text: confirmation, exercise: exerciseName, modelContext: modelContext)
        }

        engine.sendMessage(
            systemPrompt: settings.effectiveSystemPrompt,
            userMessage: combinedUserMessage,
            historyJson: historyJson,
            sink: sink,
            host: host
        )
    }

    // MARK: - Persisted memory

    /// Reads back up to `limit` persisted `CoachNoteRecord`s scoped to `exercise` (oldest first,
    /// regardless of whether they're standalone or already bridged into a finished
    /// `WorkoutRecord`), maps them to the `{"role", "content"}` shape `send_message` expects, and
    /// encodes them as JSON. This is the coach's actual cross-launch memory: a fresh app launch,
    /// with no in-memory `WorkoutSession` transcript yet, still recalls what was said/applied last
    /// time this exercise came up.
    private static func historyJSON(for exercise: String, modelContext: ModelContext, limit: Int = 24) -> String {
        var descriptor = FetchDescriptor<CoachNoteRecord>(
            predicate: #Predicate { $0.exerciseName == exercise },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descriptor.fetchLimit = 500 // generous cap before we take the trailing window below
        guard let notes = try? modelContext.fetch(descriptor) else { return "[]" }

        let entries = notes.suffix(limit).map { note -> [String: String] in
            let role = (note.kind == .user) ? "user" : "assistant"
            return ["role": role, "content": note.text]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func persistNote(kind: RecordCoachKind, text: String, exercise: String, modelContext: ModelContext) {
        guard !text.isEmpty else { return }
        let note = CoachNoteRecord(order: 0, kind: kind, text: text, exerciseName: exercise, date: .now)
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
    private let onApplied: (String) -> Void

    init(session: WorkoutSession, exerciseName: String, onApplied: @escaping (String) -> Void) {
        self.session = session
        self.exerciseName = exerciseName
        self.onApplied = onApplied
    }

    func applyTool(name: String, argsJson: String) -> String {
        DispatchQueue.main.sync { [session, exerciseName, onApplied] in
            let confirmation = session.applyCoachTool(name: name, argsJson: argsJson, transcriptExercise: exerciseName)
            onApplied(confirmation)
            return confirmation
        }
    }
}
