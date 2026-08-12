import Foundation
import FoundationModels

/// User-facing readiness for Apple's on-device foundation model. This is intentionally separate
/// from provider credentials: Apple Intelligence never needs an API key or a network endpoint.
enum AppleIntelligenceAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady

    var isAvailable: Bool { self == .available }

    var statusLabel: String {
        switch self {
        case .available: return "Ready"
        case .deviceNotEligible: return "Unavailable"
        case .notEnabled: return "Turn on"
        case .modelNotReady: return "Preparing"
        }
    }

    var message: String {
        switch self {
        case .available:
            return "Runs privately on this device with no API key."
        case .deviceNotEligible:
            return "Apple Intelligence isn't supported on this device."
        case .notEnabled:
            return "Turn on Apple Intelligence in Settings to use the on-device coach."
        case .modelNotReady:
            return "Apple Intelligence is still downloading or preparing its on-device model."
        }
    }
}

/// Native Swift provider for the Foundation Models framework. The existing Rust engine remains the
/// OpenRouter/Ollama transport; this provider deliberately routes around it because Apple's model
/// and native Tool protocol live in-process in Swift.
final class AppleIntelligenceCoachProvider: @unchecked Sendable {
    var availability: AppleIntelligenceAvailability {
        Self.availability(for: SystemLanguageModel.default.availability)
    }

    static func availability(
        for value: SystemLanguageModel.Availability
    ) -> AppleIntelligenceAvailability {
        switch value {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        @unknown default:
            return .modelNotReady
        }
    }

    func send(
        mode: CoachMode,
        systemPrompt: String,
        userMessage: String,
        historyJSON: String,
        host: AppCoachHost,
        hasLiveSession: Bool,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard availability.isAvailable else {
            onError(availability.message)
            return
        }

        let tools = Self.toolSpecs(mode: mode, hasLiveSession: hasLiveSession).map {
            AppleIntelligenceHostTool(spec: $0, host: host)
        }
        let session = LanguageModelSession(
            model: .default,
            tools: tools,
            instructions: Self.bounded(systemPrompt, maxCharacters: 1_000)
        )
        let prompt = Self.prompt(userMessage: userMessage, historyJSON: historyJSON)

        Task {
            do {
                var latest = ""
                let options = GenerationOptions(maximumResponseTokens: 384)
                for try await snapshot in session.streamResponse(to: prompt, options: options) {
                    latest = snapshot.content
                    let delta = latest
                    await MainActor.run { onDelta(delta) }
                }
                let completedResponse = latest
                await MainActor.run { onComplete(completedResponse) }
            } catch {
                let message = Self.errorMessage(for: error)
                await MainActor.run { onError(message) }
            }
        }
    }

    /// Rehydrates the small persisted transcript as plain text because Foundation Models sessions
    /// are intentionally per-turn here; Workout.md's durable CoachNoteRecord remains the source of
    /// truth across app launches and provider changes.
    static func prompt(userMessage: String, historyJSON: String) -> String {
        struct Entry: Decodable { let role: String; let content: String }
        let history: String = {
            guard let data = historyJSON.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([Entry].self, from: data),
                  !entries.isEmpty else { return "" }
            let lines = entries.suffix(2).map { entry in
                let content = bounded(entry.content, maxCharacters: 300)
                return "\(entry.role == "user" ? "Athlete" : "Coach"): \(content)"
            }
            return "Previous conversation:\n" + lines.joined(separator: "\n") + "\n\n"
        }()
        // Apple's on-device model has a deliberately compact context window. Hosted-provider
        // grounding can include doctrine, fabric traffic, reviews, and a live session all at once,
        // so retain both the start (memory/plan) and end (live state + athlete note) rather than
        // allowing a valid turn to fail before generation begins.
        return history + bounded(userMessage, maxCharacters: 2_500)
    }

    static func bounded(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters, maxCharacters > 80 else { return text }
        let marker = "\n… context trimmed for on-device model …\n"
        let remaining = maxCharacters - marker.count
        let headCount = remaining / 2
        let tailCount = remaining - headCount
        return String(text.prefix(headCount)) + marker + String(text.suffix(tailCount))
    }

    static func normalizedToolArguments(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```"), let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
            if text.hasSuffix("```") { text.removeLast(3) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any],
              let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return nil }
        return String(data: normalized, encoding: .utf8)
    }

    private static func errorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return "Apple Intelligence: \(description)"
        }
        return "Apple Intelligence couldn't complete that request. \(error.localizedDescription)"
    }
}

// MARK: - Native tools

private struct AppleIntelligenceToolSpec: Sendable {
    let name: String
    let description: String
}

/// Foundation Models guides the outer tool call and this compact string carries the existing app's
/// JSON tool contract unchanged into AppCoachHost. Keeping AppCoachHost as the sole mutation
/// boundary means Apple Intelligence and hosted providers have identical permissions and results.
@Generable
private struct AppleIntelligenceToolArguments {
    @Guide(description: "A compact valid JSON object matching this tool's contract. No markdown fences.")
    var json: String
}

private struct AppleIntelligenceHostTool: Tool {
    let spec: AppleIntelligenceToolSpec
    let host: AppCoachHost

    var name: String { spec.name }
    var description: String { spec.description + " Put the complete argument object in `json`." }

    func call(arguments: AppleIntelligenceToolArguments) async throws -> String {
        let json = AppleIntelligenceCoachProvider.normalizedToolArguments(arguments.json)
        guard json != nil else {
            return "Invalid tool arguments: expected one JSON object. Retry with compact JSON and no markdown."
        }
        return host.applyTool(name: name, argsJson: json!)
    }

}

private extension AppleIntelligenceCoachProvider {
    static func toolSpecs(mode: CoachMode, hasLiveSession: Bool) -> [AppleIntelligenceToolSpec] {
        var specs: [AppleIntelligenceToolSpec] = []

        switch mode {
        case .onboarding:
            specs += [planApply, memoryAdd]
        case .planning:
            specs += [planGet, planApply, memoryAdd]
        case .today:
            specs += [planGet, planApply]
        case .activeWorkout, .exercise:
            if hasLiveSession { specs.append(sessionApply) }
            specs += [planGet, planApply]
        case .historyReview:
            break
        }
        return specs
    }

    static let planGet = AppleIntelligenceToolSpec(
        name: "plan_get",
        description: "Return the current plan and stable IDs before editing it. Arguments: {}."
    )

    static let planApply = AppleIntelligenceToolSpec(
        name: "plan_apply",
        description: "Apply plan changes. JSON: {\"operations\":[...],\"propose\":false,\"summary\":\"...\"}. " +
            "Each operation has `op`: setPlanMeta; add/update/remove/move Session, Block, Exercise, or Set; replaceExercise; setCursor. " +
            "Use IDs from plan_get and UUIDs for new objects. Sets use reps/weight, seconds, or Tindeq seconds with targetMinKg/targetMaxKg. " +
            "For updates: omit keeps, null clears, value sets."
    )

    static let sessionApply = AppleIntelligenceToolSpec(
        name: "session_apply",
        description: "Mutate only the live workout. JSON: {\"operations\":[...]}. Operations: " +
            "{\"op\":\"adjustSet\",\"setID\":\"UUID\",\"reps\":8,\"weight\":225}; " +
            "{\"op\":\"skipSet\",\"setID\":\"UUID\"}; " +
            "{\"op\":\"substituteExercise\",\"exerciseName\":\"old\",\"newName\":\"new\"}; " +
            "{\"op\":\"addSet\",\"afterSetID\":\"UUID\",\"reps\":10,\"weight\":null}. Use plan_apply for future workouts."
    )

    static let memoryAdd = AppleIntelligenceToolSpec(
        name: "memory_add",
        description: "Remember a durable athlete fact. JSON: {\"text\":\"terse fact\",\"tags\":[\"optional\"]}."
    )

}
