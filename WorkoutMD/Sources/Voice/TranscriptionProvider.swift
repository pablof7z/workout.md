import Foundation

/// Speech-to-text transcription, abstracted behind one protocol so `VoiceInputController` (and the
/// UI it drives) never knows which engine is running underneath — see domain-primitives.md §10's
/// governing principle: **provider selection must never touch the coach domain model**. Whatever
/// text a provider ultimately produces feeds the exact same `draft` fields the keyboard feeds in
/// `CoachView`/`OnboardingView`; the coach itself only ever sees plain text.
///
/// Two conforming providers:
/// - `AppleSpeechTranscriber` — on-device by default, streams live partial results
///   (`supportsPartials == true`).
/// - `ElevenLabsTranscriber` — records locally, uploads once on `stop()`, no partials
///   (`supportsPartials == false`); the UI shows a "transcribing…" state between `stop()` being
///   called and the final text arriving.
@MainActor
protocol TranscriptionProvider {
    /// Whether `partials` ever yields intermediate text before `stop()` resolves. Cloud providers
    /// that only transcribe after the full recording is captured report `false` — the UI substitutes
    /// a "transcribing…" state instead of a live partial line.
    var supportsPartials: Bool { get }

    /// Requests whatever OS permissions the provider needs (microphone, plus speech recognition for
    /// on-device/Apple transcription). Returns `false` (rather than throwing) on denial so callers
    /// can show a calm "not authorized" state instead of an exception.
    func requestAuthorization() async -> Bool

    /// Begins capturing audio. Throws `TranscriptionError` if capture can't start (no authorization,
    /// no recognizer available, an audio session error, ...).
    func start() async throws

    /// Live partial transcripts as capture proceeds. Always exists (so callers can iterate it
    /// unconditionally), but never yields anything when `supportsPartials == false` — it simply
    /// finishes empty alongside `stop()`.
    var partials: AsyncStream<String> { get }

    /// Stops capture and returns the best final transcript. For providers with no partials, this is
    /// where the actual transcription work (e.g. the network upload) happens.
    func stop() async throws -> String

    /// Aborts capture with no result — discards any in-progress recording/upload. Safe to call from
    /// any phase, including one that already finished naturally.
    func cancel()
}

/// Errors a `TranscriptionProvider` can throw. `VoiceInputController` turns any of these into a
/// terse message for `VoiceInputView`'s `.error` phase.
enum TranscriptionError: Error, LocalizedError {
    case unauthorized
    case unavailable
    case recordingFailed(String)
    case network(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Microphone or speech recognition access wasn't granted."
        case .unavailable:
            return "Speech recognition isn't available right now."
        case .recordingFailed(let reason):
            return "Recording failed: \(reason)"
        case .network(let reason):
            return "Transcription failed: \(reason)"
        case .empty:
            return "No speech was heard."
        }
    }
}
