import AVFoundation
import Foundation
import Speech

/// On-device (falling back to server) speech transcription via `SFSpeechRecognizer` +
/// `AVAudioEngine` — the default transcription provider (domain-primitives.md §10). Streams live
/// partial results into `partials` as the athlete talks, and supports arbitrarily long recordings.
/// A speech task may mark a phrase final after a natural pause, so this keeps microphone capture
/// running and opens a fresh recognition segment for the next phrase. The controller merges those
/// segments into one durable draft.
///
/// `requestAuthorization` asks for BOTH speech-recognition and microphone permission up front, since
/// `start()` needs both to do anything useful — asking for them separately would just move the same
/// failure to a less predictable point.
@MainActor
final class AppleSpeechTranscriber: TranscriptionProvider {
    let supportsPartials = true

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var partialsContinuation: AsyncStream<String>.Continuation?
    private var latestTranscript = ""
    private var isTapInstalled = false

    /// Bridges `SFSpeechRecognitionTask`'s callback-based final result back to the `async` `stop()`
    /// call that's waiting on it.
    private var stopContinuation: CheckedContinuation<String, Error>?

    init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    var partials: AsyncStream<String> {
        AsyncStream { continuation in
            self.partialsContinuation = continuation
        }
    }

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        let micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        return micGranted
    }

    func start() async throws {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        latestTranscript = ""

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw TranscriptionError.recordingFailed(error.localizedDescription)
        }

        do {
            try startRecognitionSegment()
        } catch {
            teardownAudio()
            throw error
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            teardownAudio()
            throw TranscriptionError.recordingFailed(error.localizedDescription)
        }
    }

    /// Starts one recognizer phrase against the already-running microphone. Each segment owns its
    /// tap's request capture, so when the system finalizes after silence we can replace it without
    /// stopping audio or losing the next phrase.
    private func startRecognitionSegment() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        request = recognitionRequest

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        if isTapInstalled {
            inputNode.removeTap(onBus: 0)
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
        }
        isTapInstalled = true

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.handleRecognitionUpdate(result: result, error: error)
            }
        }
    }

    private func handleRecognitionUpdate(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            latestTranscript = result.bestTranscription.formattedString
            partialsContinuation?.yield(latestTranscript)
            if result.isFinal {
                if stopContinuation != nil {
                    finishStop(with: .success(latestTranscript))
                } else {
                    // A pause is a boundary between recognition segments, not the end of the
                    // athlete's dictation. Keep the mic live and listen for the next phrase.
                    try? startRecognitionSegment()
                }
            }
            return
        }
        if let error {
            // A cancellation triggered by our own `cancel()`/`stop()` teardown surfaces here too;
            // if we already have recognized words, return those rather than turning a deliberate
            // stop after a pause into a data-loss error.
            if stopContinuation != nil, !latestTranscript.isEmpty {
                finishStop(with: .success(latestTranscript))
            } else {
                finishStop(with: .failure(TranscriptionError.recordingFailed(error.localizedDescription)))
            }
        }
    }

    /// Resolves whichever `stop()` call is currently awaiting the final transcript, if any — a no-op
    /// otherwise (e.g. `cancel()` already tore things down with no waiter left).
    private func finishStop(with result: Result<String, Error>) {
        guard let stopContinuation else { return }
        self.stopContinuation = nil
        switch result {
        case .success(let text):
            stopContinuation.resume(returning: text)
        case .failure(let error):
            stopContinuation.resume(throwing: error)
        }
    }

    func stop() async throws -> String {
        guard task != nil else { throw TranscriptionError.recordingFailed("Recording was not active.") }

        // Ending the audio tells the recognizer no more buffers are coming; it then delivers one
        // last `isFinal` result through the callback above, which resolves this continuation.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.stopContinuation = continuation
            teardownAudio()
            request?.endAudio()
        }
    }

    func cancel() {
        finishStop(with: .success(""))
        task?.cancel()
        task = nil
        teardownAudio()
        request = nil
        partialsContinuation?.finish()
        partialsContinuation = nil
    }

    private func teardownAudio() {
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
