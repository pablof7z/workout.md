import XCTest
@testable import WorkoutMD

/// Unit tests for the voice-input state machine (domain-primitives.md §10). Real microphone/speech
/// hardware isn't available in a unit test, so these drive `VoiceInputController` against a scriptable
/// `MockTranscriptionProvider` instead of `AppleSpeechTranscriber`/`ElevenLabsTranscriber` — the whole
/// point of `TranscriptionProvider` being a protocol the controller is initialized with
/// (`VoiceInputController.init(provider:)`), never a concrete type it constructs itself.
///
/// `start()`/`finish()` are `async` on the controller specifically so these tests can await the
/// resulting phase deterministically instead of racing a detached `Task`.
@MainActor
final class VoiceInputTests: XCTestCase {

    // MARK: - 1. Happy path: start → partials → finish → review

    func testStartEntersRecordingAndPartialsFlowIntoPartialText() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.scriptedPartials = ["How", "How did", "How did that feel"]
        mock.stopResult = .success("How did that feel")
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(mock.startCallCount, 1)

        await waitUntil { controller.partialText == "How did that feel" }
        XCTAssertEqual(controller.partialText, "How did that feel")
    }

    func testFinishEntersReviewWithTheFinalTranscript() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.stopResult = .success("Squats felt heavy today")
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        await controller.finish()

        XCTAssertEqual(controller.phase, .review("Squats felt heavy today"))
    }

    /// The review text is just a `String` handed back through `.review(_:)` — nothing in the
    /// controller locks it. `VoiceInputView` seeds its editable `TextEditor` from exactly this value
    /// and later hands whatever the user edited it to back through `onSubmit`, so "the submitted text
    /// is what the caller receives" reduces to: the value in `.review` is the athlete's to change
    /// before anything is ever sent to the coach.
    func testReviewTextIsFreelyEditableBeforeSubmission() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.stopResult = .success("Bench felt heavy")
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        await controller.finish()

        guard case .review(let transcript) = controller.phase else {
            return XCTFail("Expected .review, got \(controller.phase)")
        }
        // Simulates the caller (VoiceInputView's TextEditor binding) editing the seeded text — the
        // controller has no opinion about this; whatever the caller submits is what the coach sees.
        var edited = transcript
        edited += ", added an extra warm-up set"
        XCTAssertNotEqual(edited, transcript)
        XCTAssertTrue(edited.hasPrefix(transcript))
    }

    /// A cloud-style provider (`supportsPartials == false`, mirroring `ElevenLabsTranscriber`) must
    /// still resolve into a normal `.review`, visibly passing through `.transcribing` while `stop()`'s
    /// upload is in flight — nothing ever appears in `partialText`.
    func testNonPartialProviderPassesThroughTranscribingThenReview() async {
        let mock = MockTranscriptionProvider(supportsPartials: false)
        mock.stopResult = .success("Uploaded and transcribed remotely")
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertFalse(controller.supportsPartials)
        XCTAssertTrue(controller.partialText.isEmpty)

        await controller.finish()
        XCTAssertEqual(controller.phase, .review("Uploaded and transcribed remotely"))
    }

    /// If a partials-supporting provider's `stop()` ever returns an empty string despite live
    /// partials having arrived, the controller falls back to the last partial rather than handing the
    /// athlete a blank review screen.
    func testEmptyFinalTextFallsBackToLastPartial() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.scriptedPartials = ["Partial only"]
        mock.stopResult = .success("")
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        await waitUntil { controller.partialText == "Partial only" }
        await controller.finish()

        XCTAssertEqual(controller.phase, .review("Partial only"))
    }

    /// Apple's speech recognizer is allowed to begin a fresh partial hypothesis after a natural
    /// pause. The visible draft must retain the earlier words and append the new fragment, rather
    /// than replacing the whole draft with only what came after the pause.
    func testPartialAfterPauseAppendsInsteadOfReplacingEarlierDictation() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.scriptedPartials = ["I want to get stronger", "and train three days a week"]
        mock.stopResult = .success("and train three days a week")
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        await waitUntil { controller.partialText == "I want to get stronger and train three days a week" }
        XCTAssertEqual(controller.partialText, "I want to get stronger and train three days a week")

        await controller.finish()
        XCTAssertEqual(controller.phase, .review("I want to get stronger and train three days a week"))
    }

    func testPartialWithWordOverlapAppendsOnlyNewWords() {
        XCTAssertEqual(
            VoiceInputController.mergingRecognizedText("I want to get stronger", with: "stronger and train three days"),
            "I want to get stronger and train three days"
        )
    }

    // MARK: - 2. Cancel

    func testCancelFromRecordingReturnsToIdleWithNoResult() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.scriptedPartials = ["Some words"]
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        await waitUntil { controller.partialText == "Some words" }

        controller.cancel()

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.partialText, "")
        XCTAssertEqual(mock.cancelCallCount, 1)
    }

    func testCancelFromReviewDiscardsTheTranscript() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.stopResult = .success("Should be discarded")
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        await controller.finish()
        XCTAssertEqual(controller.phase, .review("Should be discarded"))

        controller.cancel()
        XCTAssertEqual(controller.phase, .idle)
    }

    // MARK: - 3. Failure + retry

    func testStopFailureEntersErrorPhase() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.stopResult = .failure(TranscriptionError.network("connection reset"))
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        await controller.finish()

        guard case .error = controller.phase else {
            return XCTFail("Expected .error, got \(controller.phase)")
        }
    }

    func testAuthorizationDenialEntersErrorPhase() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.authorizationResult = false
        let controller = VoiceInputController(provider: mock)

        await controller.start()

        guard case .error = controller.phase else {
            return XCTFail("Expected .error, got \(controller.phase)")
        }
        XCTAssertEqual(mock.startCallCount, 0, "capture never starts without authorization")
    }

    func testRetryAfterErrorSucceeds() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        mock.stopResult = .failure(TranscriptionError.network("timed out"))
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        await controller.finish()
        guard case .error = controller.phase else {
            return XCTFail("Expected .error before retry, got \(controller.phase)")
        }

        // Retry: the provider now succeeds (e.g. the network recovered).
        mock.stopResult = .success("Recovered after retry")
        await controller.start()
        XCTAssertEqual(controller.phase, .recording, "start() from .error re-enters recording")

        await controller.finish()
        XCTAssertEqual(controller.phase, .review("Recovered after retry"))
    }

    func testStartIsIgnoredWhileAlreadyRecording() async {
        let mock = MockTranscriptionProvider(supportsPartials: true)
        let controller = VoiceInputController(provider: mock)

        await controller.start()
        XCTAssertEqual(controller.phase, .recording)
        XCTAssertEqual(mock.startCallCount, 1)

        await controller.start()
        XCTAssertEqual(mock.startCallCount, 1, "a second start() while already recording is a no-op")
    }

    // MARK: - 4. Provider selection (AppSettings round-trip + matching provider kind)

    func testTranscriptionProviderKindRoundTripsThroughUserDefaults() {
        let suiteName = "VoiceInputTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.transcriptionProviderKind, .apple, "Apple on-device is the default")

        first.transcriptionProviderKind = .elevenLabs

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.transcriptionProviderKind, .elevenLabs, "persisted across a fresh AppSettings instance")
    }

    func testMakeProviderBuildsTheMatchingConcreteProviderType() {
        let apple = VoiceInputController.makeProvider(kind: .apple)
        XCTAssertTrue(apple is AppleSpeechTranscriber)

        let elevenLabs = VoiceInputController.makeProvider(kind: .elevenLabs)
        XCTAssertTrue(elevenLabs is ElevenLabsTranscriber)
    }

    // MARK: - Helpers

    /// Polls `condition` on the main actor until it's true or a short timeout elapses — used instead
    /// of a fixed sleep to wait for `MockTranscriptionProvider`'s scripted partials to flow through
    /// `VoiceInputController`'s background partials-pumping `Task`, without coupling the test to a
    /// specific delay.
    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

// MARK: - MockTranscriptionProvider

/// A fully scriptable `TranscriptionProvider` — no `Speech`/`AVFoundation` involved — so
/// `VoiceInputTests` can drive `VoiceInputController` deterministically. Every real capture step
/// (`requestAuthorization`, `start`, `stop`) is a scripted, instant result rather than touching
/// hardware.
@MainActor
private final class MockTranscriptionProvider: TranscriptionProvider {
    let supportsPartials: Bool

    var authorizationResult = true
    var startError: Error?
    var stopResult: Result<String, Error> = .success("")
    /// Yielded, in order, into `partials` as soon as something iterates it — stands in for a real
    /// provider's live partial transcripts arriving over time.
    var scriptedPartials: [String] = []

    private(set) var startCallCount = 0
    private(set) var cancelCallCount = 0

    init(supportsPartials: Bool) {
        self.supportsPartials = supportsPartials
    }

    var partials: AsyncStream<String> {
        AsyncStream { continuation in
            for partial in scriptedPartials {
                continuation.yield(partial)
            }
            // Deliberately left open (not `.finish()`ed) — a real provider's partials stream stays
            // open until capture stops; `VoiceInputController` tears down its consuming `Task` itself
            // via `cancel()`/after `finish()`, matching how it treats a real provider.
        }
    }

    func requestAuthorization() async -> Bool { authorizationResult }

    func start() async throws {
        startCallCount += 1
        if let startError { throw startError }
    }

    func stop() async throws -> String {
        switch stopResult {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }

    func cancel() {
        cancelCallCount += 1
    }
}
