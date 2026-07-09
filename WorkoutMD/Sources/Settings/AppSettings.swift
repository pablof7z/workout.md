import Foundation
import Observation

/// Which LLM provider the coach engine talks to. Mirrors `ProviderConfig`'s two cases, minus the
/// credentials (those live in the Keychain via `CoachSecrets`, never here).
enum CoachProviderKind: String, Codable, CaseIterable, Identifiable {
    case openRouter
    case ollama

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama"
        }
    }

    /// Shown as a `TextField` placeholder so the free-text model field isn't a blank mystery.
    var modelPlaceholder: String {
        switch self {
        case .openRouter: return "anthropic/claude-3.5-sonnet"
        case .ollama: return "llama3.1"
        }
    }
}

/// Coach voice/verbosity — adjusts the system prompt rather than being its own separate setting the
/// model has to interpret, so it composes with a custom system-prompt override too.
enum CoachVerbosity: String, Codable, CaseIterable, Identifiable {
    case concise
    case balanced
    case verbose

    var id: String { rawValue }

    var label: String {
        switch self {
        case .concise: return "Concise"
        case .balanced: return "Balanced"
        case .verbose: return "Verbose"
        }
    }

    /// Appended to the base system prompt (default or override). Empty for `.balanced`, which is
    /// exactly the base prompt's own default voice.
    var promptSuffix: String {
        switch self {
        case .concise:
            return " Keep replies to a single short sentence — or none at all when a tool call " +
                "already says everything the athlete needs."
        case .balanced:
            return ""
        case .verbose:
            return " You may use two or three sentences to explain the reasoning behind a change " +
                "before or after calling a tool."
        }
    }
}

/// App-wide, non-secret preferences: coach provider/model/voice, the GitHub sync repo name, and
/// training goals/dislikes. Backed by `UserDefaults` — nothing stored here is sensitive. The
/// OpenRouter/Ollama API keys and the GitHub token live in the Keychain instead (`CoachSecrets`,
/// `GitHubAuth`) and are never written to `UserDefaults` or logged.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    // MARK: Coach / AI

    var providerKind: CoachProviderKind {
        didSet { defaults.set(providerKind.rawValue, forKey: Keys.providerKind) }
    }
    var ollamaBaseURL: String {
        didSet { defaults.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL) }
    }
    var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }
    var verbosity: CoachVerbosity {
        didSet { defaults.set(verbosity.rawValue, forKey: Keys.verbosity) }
    }
    /// Empty means "use `default_coach_system_prompt()` from the Rust core."
    var systemPromptOverride: String {
        didSet { defaults.set(systemPromptOverride, forKey: Keys.systemPromptOverride) }
    }

    // MARK: Sync (GitHub)

    var githubRepoName: String {
        didSet { defaults.set(githubRepoName, forKey: Keys.githubRepoName) }
    }

    // MARK: Goals & preferences

    var primaryGoal: String {
        didSet { defaults.set(primaryGoal, forKey: Keys.primaryGoal) }
    }
    var sessionLengthMinutes: Int {
        didSet { defaults.set(sessionLengthMinutes, forKey: Keys.sessionLengthMinutes) }
    }
    var dislikedExercises: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(dislikedExercises) {
                defaults.set(data, forKey: Keys.dislikedExercises)
            }
        }
    }

    private enum Keys {
        static let providerKind = "coach.providerKind"
        static let ollamaBaseURL = "coach.ollamaBaseURL"
        static let model = "coach.model"
        static let verbosity = "coach.verbosity"
        static let systemPromptOverride = "coach.systemPromptOverride"
        static let githubRepoName = "sync.githubRepoName"
        static let primaryGoal = "prefs.primaryGoal"
        static let sessionLengthMinutes = "prefs.sessionLengthMinutes"
        static let dislikedExercises = "prefs.dislikedExercises"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        providerKind = CoachProviderKind(rawValue: defaults.string(forKey: Keys.providerKind) ?? "") ?? .ollama
        ollamaBaseURL = {
            let stored = defaults.string(forKey: Keys.ollamaBaseURL) ?? ""
            return stored.isEmpty ? "http://localhost:11434" : stored
        }()
        model = defaults.string(forKey: Keys.model) ?? ""
        verbosity = CoachVerbosity(rawValue: defaults.string(forKey: Keys.verbosity) ?? "") ?? .balanced
        systemPromptOverride = defaults.string(forKey: Keys.systemPromptOverride) ?? ""

        githubRepoName = {
            let stored = defaults.string(forKey: Keys.githubRepoName) ?? ""
            return stored.isEmpty ? "workout-log" : stored
        }()

        primaryGoal = defaults.string(forKey: Keys.primaryGoal) ?? "Hypertrophy"
        sessionLengthMinutes = (defaults.object(forKey: Keys.sessionLengthMinutes) as? Int) ?? 45
        if let data = defaults.data(forKey: Keys.dislikedExercises),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            dislikedExercises = decoded
        } else {
            dislikedExercises = []
        }
    }

    /// The system prompt actually sent to the coach engine on every turn: the user's override if
    /// they set one, otherwise the Rust core's own `default_coach_system_prompt()`, with the
    /// verbosity suffix appended either way.
    var effectiveSystemPrompt: String {
        let trimmedOverride = systemPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedOverride.isEmpty ? defaultCoachSystemPrompt() : trimmedOverride
        return base + verbosity.promptSuffix
    }

    /// Builds the `ProviderConfig` the coach engine needs, given a credential freshly read from the
    /// Keychain (`nil`/empty is passed through as "no key" rather than an empty-string key).
    func providerConfig(apiKey: String?) -> ProviderConfig {
        let key = (apiKey?.isEmpty == false) ? apiKey : nil
        switch providerKind {
        case .openRouter:
            return .openRouter(apiKey: key ?? "", baseUrl: nil)
        case .ollama:
            return .ollama(baseUrl: ollamaBaseURL, apiKey: key)
        }
    }
}
