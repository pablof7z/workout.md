import AVFoundation
import Foundation

/// Cloud transcription via ElevenLabs Speech-to-Text (domain-primitives.md §10's optional provider).
/// Unlike `AppleSpeechTranscriber`, this only needs microphone permission — there's no on-device
/// speech-recognition entitlement involved, since the audio is just recorded locally to a temp
/// `.m4a` file and uploaded once, on `stop()`. `supportsPartials` is `false`: nothing is known about
/// the transcript until the upload's response comes back, so `VoiceInputController` shows a
/// "transcribing…" state between `stop()` being called and its result arriving, rather than a live
/// partial line.
@MainActor
final class ElevenLabsTranscriber: TranscriptionProvider {
    let supportsPartials = false

    private static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    private static let modelID = "scribe_v1"

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    /// Never yields anything (see `supportsPartials`) — exists only so callers can iterate the
    /// stream unconditionally like they do for `AppleSpeechTranscriber`. Finished immediately.
    var partials: AsyncStream<String> {
        AsyncStream { continuation in continuation.finish() }
    }

    /// Microphone access only — no speech-recognition permission is relevant to a cloud upload.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw TranscriptionError.recordingFailed(error.localizedDescription)
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            self.recorder = recorder
            self.fileURL = url
        } catch {
            throw TranscriptionError.recordingFailed(error.localizedDescription)
        }
    }

    /// Stops the local recording, then uploads the captured audio to ElevenLabs and returns its
    /// transcript. This is where all the real latency of this provider lives — there's no partial
    /// progress to report in between (see `supportsPartials`).
    func stop() async throws -> String {
        guard let recorder, let fileURL else {
            throw TranscriptionError.recordingFailed("Recording was not active.")
        }
        recorder.stop()
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        defer { try? FileManager.default.removeItem(at: fileURL) }

        let storedKey = (try? CoachSecrets.elevenLabsAPIKey()) ?? nil
        guard let apiKey = storedKey, !apiKey.isEmpty else {
            throw TranscriptionError.unauthorized
        }

        let audioData = try Data(contentsOf: fileURL)
        guard !audioData.isEmpty else { throw TranscriptionError.empty }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(boundary: boundary, modelID: Self.modelID, audioData: audioData, filename: fileURL.lastPathComponent)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptionError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.network("No response from ElevenLabs.")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw TranscriptionError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TranscriptionError.network(message)
        }
        guard let decoded = try? JSONDecoder().decode(ElevenLabsTranscriptionResponse.self, from: data) else {
            throw TranscriptionError.network("Could not parse the transcription response.")
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.empty }
        return text
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    /// Hand-built multipart body — `model_id` as a plain field, `file` as the audio attachment, per
    /// ElevenLabs' `POST /v1/speech-to-text` contract.
    private static func multipartBody(boundary: String, modelID: String, audioData: Data, filename: String) -> Data {
        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model_id", value: modelID)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

private struct ElevenLabsTranscriptionResponse: Decodable {
    let text: String
}
