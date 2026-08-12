import Foundation
import Observation

/// The voice-input state machine (domain-primitives.md §10). Owns exactly one `TranscriptionProvider`
/// instance per dictation attempt and walks it through: authorize → record (with live partials where
/// supported) → transcribe (cloud providers only) → an EDITABLE review of the final text → submit.
/// Cancellation and failure/retry are first-class phases, not afterthoughts.
///
/// The provider is injected (`init(provider:)`) so tests never construct `AppleSpeechTranscriber`/
/// `ElevenLabsTranscriber` (which would touch `Speech`/`AVFoundation`) — see `VoiceInputTests`'
/// `MockTranscriptionProvider`. The convenience `init(settings:)` is what real UI call sites use; it
/// builds the provider matching `AppSettings.transcriptionProviderKind` via `makeProvider(kind:)`.
@MainActor
@Observable
final class VoiceInputController {
    enum Phase: Equatable {
        case idle
        case authorizing
        case recording
        case transcribing
        case review(String)
        case error(String)
    }

    private(set) var phase: Phase = .idle
    /// Live partial transcript, updated while `phase == .recording`. It is a durable draft, not
    /// merely the recognizer's latest hypothesis: Apple can start a fresh hypothesis after a
    /// natural thinking pause. That new fragment must extend the words already shown, never erase
    /// them. It stays populated through `.transcribing`/`.review` so a provider whose `stop()`
    /// returns an empty string can still fall back to the last partial seen (see `finish()`).
    private(set) var partialText = ""

    private let provider: TranscriptionProvider
    private var partialsTask: Task<Void, Never>?

    var supportsPartials: Bool { provider.supportsPartials }

    init(provider: TranscriptionProvider) {
        self.provider = provider
    }

    convenience init(settings: AppSettings = .shared) {
        self.init(provider: Self.makeProvider(kind: settings.transcriptionProviderKind))
    }

    /// The provider-selection seam itself (domain-primitives.md §10's governing principle): this is
    /// the ONLY place `TranscriptionProviderKind` ever turns into a concrete provider. Nothing
    /// downstream of `VoiceInputController` — not `VoiceInputView`, not the coach — ever asks which
    /// provider produced the text it's holding.
    static func makeProvider(kind: TranscriptionProviderKind) -> TranscriptionProvider {
        switch kind {
        case .apple: return AppleSpeechTranscriber()
        case .elevenLabs: return ElevenLabsTranscriber()
        }
    }

    /// Requests authorization, then begins capture. Safe to call again from `.error` (used as the
    /// retry path — see `VoiceInputView`'s Retry button) or from a fresh `.idle` state; a call while
    /// already recording/transcribing is ignored. `async` (rather than fire-and-forget) so both real
    /// callers (`Task { await controller.start() }` in `MicButton`) and tests can deterministically
    /// await the resulting phase instead of racing a detached `Task`.
    func start() async {
        guard phase == .idle || isErrorPhase else { return }
        partialText = ""
        phase = .authorizing

        let authorized = await provider.requestAuthorization()
        guard authorized else {
            phase = .error(TranscriptionError.unauthorized.errorDescription ?? "Not authorized.")
            return
        }
        do {
            try await provider.start()
            phase = .recording
            pumpPartials()
        } catch {
            phase = .error(Self.message(for: error))
        }
    }

    private func pumpPartials() {
        partialsTask?.cancel()
        partialsTask = Task {
            for await text in provider.partials {
                guard !Task.isCancelled else { return }
                partialText = Self.mergingRecognizedText(partialText, with: text)
            }
        }
    }

    /// Stops capture. For a provider with live partials, the final transcript is normally what
    /// `stop()` itself returns; if a provider ever returns an empty string despite partials having
    /// arrived, the last partial is used as a fallback so a real utterance never turns into a blank
    /// review screen. For a provider with no partials (ElevenLabs), `phase` visibly passes through
    /// `.transcribing` while the upload is in flight. `async` for the same testability reason as
    /// `start()`.
    func finish() async {
        guard phase == .recording else { return }
        if !provider.supportsPartials {
            phase = .transcribing
        }

        do {
            let finalText = try await provider.stop()
            partialsTask?.cancel()
            let resolved = Self.mergingRecognizedText(partialText, with: finalText)
            phase = .review(resolved)
        } catch {
            partialsTask?.cancel()
            phase = .error(Self.message(for: error))
        }
    }

    /// Aborts the current attempt with no result — from any phase, including a finished one. Back to
    /// `.idle`; the caller (`VoiceInputView`) is expected to dismiss its presentation on top of this.
    func cancel() {
        partialsTask?.cancel()
        partialsTask = nil
        provider.cancel()
        partialText = ""
        phase = .idle
    }

    private var isErrorPhase: Bool {
        if case .error = phase { return true }
        return false
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }

    /// Turns a recognizer update into an append-only dictation draft. Recognition APIs generally
    /// resend their complete current hypothesis, but after a pause they may instead deliver only
    /// the next phrase. Prefer that complete hypothesis when it extends the existing draft; keep
    /// the existing draft if the new one is a shorter revision; otherwise append only the portion
    /// not shared at the word boundary.
    ///
    /// This deliberately favors preserving the athlete's words over aggressively rewriting them.
    /// The final review remains editable, so a harmless duplicated word is recoverable; silently
    /// losing a thought during dictation is not.
    static func mergingRecognizedText(_ existing: String, with incoming: String) -> String {
        let current = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = incoming.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !update.isEmpty else { return current }
        guard !current.isEmpty else { return update }

        if update.localizedCaseInsensitiveContains(current) { return update }
        if current.localizedCaseInsensitiveContains(update) { return current }

        let currentWords = current.split(whereSeparator: \.isWhitespace)
        let updateWords = update.split(whereSeparator: \.isWhitespace)
        let maximumOverlap = min(currentWords.count, updateWords.count)

        for overlap in stride(from: maximumOverlap, through: 1, by: -1) {
            let suffix = currentWords.suffix(overlap).map { $0.lowercased() }
            let prefix = updateWords.prefix(overlap).map { $0.lowercased() }
            if suffix == prefix {
                let novelWords = updateWords.dropFirst(overlap)
                guard !novelWords.isEmpty else { return current }
                return current + " " + novelWords.joined(separator: " ")
            }
        }

        return current + " " + update
    }
}
