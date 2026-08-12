import Foundation
import Observation

/// Which LLM provider the coach talks to. OpenRouter/Ollama use the Rust engine; Apple Intelligence
/// uses Foundation Models directly in Swift and needs neither credentials nor a model id.
enum CoachProviderKind: String, Codable, CaseIterable, Identifiable {
    case openRouter
    case ollama
    case appleIntelligence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    /// Shown as a `TextField` placeholder so the free-text model field isn't a blank mystery. Format
    /// hints only — never a real model id, and never written into `AppSettings` as a default (see
    /// `ModelSelectorView`/`ConnectCoachView.fetchFirstModelID`, which fetch a real default instead).
    var modelPlaceholder: String {
        switch self {
        case .openRouter: return "provider/model"
        case .ollama: return "model-name"
        case .appleIntelligence: return "On-device system model"
        }
    }

    var supportsBYOK: Bool { self != .appleIntelligence }
    var usesModelPicker: Bool { self != .appleIntelligence }
}

/// Which speech-to-text engine `VoiceInputController` builds (domain-primitives.md §10). Mirrors
/// `CoachProviderKind`'s shape, but is entirely independent of it — voice transcription is an input
/// method feeding the same text fields the keyboard feeds, never something the coach domain model
/// sees a provider tag for.
enum TranscriptionProviderKind: String, Codable, CaseIterable, Identifiable {
    case apple
    case elevenLabs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: return "Apple (on-device)"
        case .elevenLabs: return "ElevenLabs (cloud)"
        }
    }

    var detail: String {
        switch self {
        case .apple: return "Free, on-device, works offline. Live partial transcript while you talk."
        case .elevenLabs: return "Cloud transcription. Requires an ElevenLabs API key; no live partials."
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

/// The two capability tiers the coach model picker exposes. Replaces the old three per-task-role
/// models (`liveCoach`/`planGeneration`/`externalReview`) — those were never really different jobs,
/// just the same coach calling the same general tools under different labels. Now there's one
/// default tier the coach runs on for everything, and a stronger tier the AGENT ITSELF switches to,
/// mid-conversation, via the `escalate_to_reasoning` tool when a task demands it (building a whole
/// plan from a vague description, a complex repair) — see `CoachController.converse`'s `forceTier`
/// re-run. The Rust engine already accepts a model each time it is configured, so this is a Swift
/// settings/runtime concern rather than a new UniFFI contract.
enum CoachModelTier: String, Codable, CaseIterable, Identifiable {
    case fast
    case reasoning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fast: return "Fast"
        case .reasoning: return "Reasoning"
        }
    }

    var detail: String {
        switch self {
        case .fast:
            return "Everyday coaching, quick edits, and chat."
        case .reasoning:
            return "Harder tasks like building a plan or a complex repair — the coach switches to this itself when needed."
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
    /// The default tier the coach runs on for everything. No hardcoded default — empty until the
    /// athlete connects a provider (`ConnectCoachView.finishConnection`) or picks one explicitly in
    /// Settings (`ModelTierSettingsView`), both via the fetched model picker.
    var fastModel: String {
        didSet { defaults.set(fastModel, forKey: Keys.fastModel) }
    }
    /// The stronger tier the coach switches ITSELF to via `escalate_to_reasoning` when a turn demands
    /// it. Empty means "not configured yet" — `model(for:.reasoning)` falls back to `fastModel` in
    /// that case, so escalation is always a no-op until the athlete deliberately picks a distinct
    /// reasoning model.
    var reasoningModel: String {
        didSet { defaults.set(reasoningModel, forKey: Keys.reasoningModel) }
    }
    var verbosity: CoachVerbosity {
        didSet { defaults.set(verbosity.rawValue, forKey: Keys.verbosity) }
    }
    /// Empty means "use `default_coach_system_prompt()` from the Rust core."
    var systemPromptOverride: String {
        didSet { defaults.set(systemPromptOverride, forKey: Keys.systemPromptOverride) }
    }

    // MARK: Voice

    /// Which `TranscriptionProvider` `VoiceInputController` builds — Apple on-device by default
    /// (domain-primitives.md §10). The credential (when `elevenLabs`) lives in Keychain via
    /// `CoachSecrets.elevenLabsAPIKey`, never here.
    var transcriptionProviderKind: TranscriptionProviderKind {
        didSet { defaults.set(transcriptionProviderKind.rawValue, forKey: Keys.transcriptionProviderKind) }
    }

    // MARK: Sync (GitHub)

    var githubRepoName: String {
        didSet { defaults.set(githubRepoName, forKey: Keys.githubRepoName) }
    }

    // MARK: Sync (iCloud)

    /// Whether the app mirrors session Markdown into the iCloud ubiquity container (`ICloudSync`).
    /// Off by default — opt-in, same as GitHub. Fully independent of `githubRepoName`/GitHub auth:
    /// both are separate mirrors of the same rendered Markdown and can be toggled independently
    /// without affecting each other (see `SyncManager.commitSession`).
    var icloudSyncEnabled: Bool {
        didSet { defaults.set(icloudSyncEnabled, forKey: Keys.icloudSyncEnabled) }
    }

    // MARK: Coach fabric (tenex-edge NIP-29)

    /// Whether the coach should join the user's tenex-edge fabric at all — gates both outbound
    /// posting (session summaries, notable plan changes) and the inbound subscription. The nsec
    /// itself lives in the Keychain (`FabricSecrets`), never here.
    var fabricEnabled: Bool {
        didSet { defaults.set(fabricEnabled, forKey: Keys.fabricEnabled) }
    }
    /// Comma/newline-separated relay URL(s) — see `fabricRelaysList` for the parsed form `configure`
    /// actually takes.
    var fabricRelay: String {
        didSet { defaults.set(fabricRelay, forKey: Keys.fabricRelay) }
    }
    /// The profile indexer relay (kind:0 only — never targeted for chat/group events). Empty means
    /// "no indexer", passed to `configure` as `nil`.
    var fabricIndexerRelay: String {
        didSet { defaults.set(fabricIndexerRelay, forKey: Keys.fabricIndexerRelay) }
    }
    /// The NIP-29 channel id/slug the coach joins. Membership beyond read access is admin-granted —
    /// see `FabricController`'s doc comment and the Settings footer for the `tenex-edge channel add`
    /// hint surfaced to the user.
    var fabricChannel: String {
        didSet { defaults.set(fabricChannel, forKey: Keys.fabricChannel) }
    }
    var fabricDisplayName: String {
        didSet { defaults.set(fabricDisplayName, forKey: Keys.fabricDisplayName) }
    }
    var fabricAbout: String {
        didSet { defaults.set(fabricAbout, forKey: Keys.fabricAbout) }
    }

    /// `fabricRelay` split on commas/newlines into the `sequence<string>` `NostrCoach.configure`
    /// expects, trimmed and with blanks dropped.
    var fabricRelaysList: [String] {
        fabricRelay
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Onboarding

    /// Whether the first-run `OnboardingView` sequence has been shown and dismissed. Set once, on
    /// "Get started" — never reset by the app itself.
    var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Keys.hasOnboarded) }
    }

    // MARK: Training doctrine (M7)

    /// Whether uploaded training-doctrine documents (`DoctrineStore`) are folded into the coach's
    /// grounding context. On by default — once a user bothers adding doctrine, they expect it used
    /// immediately, not behind a second opt-in. See `CoachController.send`'s `doctrineContext`.
    var doctrineEnabled: Bool {
        didSet { defaults.set(doctrineEnabled, forKey: Keys.doctrineEnabled) }
    }

    private enum Keys {
        static let providerKind = "coach.providerKind"
        static let ollamaBaseURL = "coach.ollamaBaseURL"
        /// Legacy single global model key, pre-tiers. Read only as a migration fallback in `init` —
        /// nothing writes it anymore.
        static let legacyModel = "coach.model"
        /// Legacy per-role keys, pre-tiers (`CoachModelRole`). Read only as migration fallbacks in
        /// `init` — nothing writes them anymore. `externalReview` had no analogue worth migrating
        /// (external-change review is now just a normal fast-tier turn).
        static let legacyLiveCoachModel = "coach.model.liveCoach"
        static let legacyPlanGenerationModel = "coach.model.planGeneration"
        static let fastModel = "coach.model.fast"
        static let reasoningModel = "coach.model.reasoning"
        static let verbosity = "coach.verbosity"
        static let systemPromptOverride = "coach.systemPromptOverride"
        static let transcriptionProviderKind = "voice.transcriptionProviderKind"
        static let githubRepoName = "sync.githubRepoName"
        static let icloudSyncEnabled = "sync.icloudSyncEnabled"
        static let fabricEnabled = "fabric.enabled"
        static let fabricRelay = "fabric.relay"
        static let fabricIndexerRelay = "fabric.indexerRelay"
        static let fabricChannel = "fabric.channel"
        static let fabricDisplayName = "fabric.displayName"
        static let fabricAbout = "fabric.about"
        static let hasOnboarded = "onboarding.hasOnboarded"
        static let doctrineEnabled = "prefs.doctrineEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // OpenRouter is the default rather than Ollama: a local Ollama server at `localhost` can
        // never be reachable from a real iPhone (only the Simulator, which shares the Mac's
        // network namespace), so defaulting to it made every first-run coach turn dump a raw
        // connection error. OpenRouter at least fails calmly into `CoachView`'s "no key yet" state
        // (see `isCoachConfigured`) until the athlete adds a key in Settings.
        providerKind = CoachProviderKind(rawValue: defaults.string(forKey: Keys.providerKind) ?? "") ?? .openRouter
        ollamaBaseURL = {
            let stored = defaults.string(forKey: Keys.ollamaBaseURL) ?? ""
            return stored.isEmpty ? "http://localhost:11434" : stored
        }()
        // Migration: a fresh `coach.model.fast`/`coach.model.reasoning` value wins if present;
        // otherwise fall back to the old per-role key, and — for `fastModel` only — all the way back
        // to the original pre-role single `coach.model` global, so nobody who connected a provider
        // before this refactor lands back at an empty, unconfigured coach.
        let legacyGlobalModel = defaults.string(forKey: Keys.legacyModel) ?? ""
        fastModel = defaults.string(forKey: Keys.fastModel)
            ?? defaults.string(forKey: Keys.legacyLiveCoachModel)
            ?? legacyGlobalModel
        reasoningModel = defaults.string(forKey: Keys.reasoningModel)
            ?? defaults.string(forKey: Keys.legacyPlanGenerationModel)
            ?? ""
        verbosity = CoachVerbosity(rawValue: defaults.string(forKey: Keys.verbosity) ?? "") ?? .balanced
        systemPromptOverride = defaults.string(forKey: Keys.systemPromptOverride) ?? ""

        transcriptionProviderKind = TranscriptionProviderKind(
            rawValue: defaults.string(forKey: Keys.transcriptionProviderKind) ?? ""
        ) ?? .apple

        githubRepoName = {
            let stored = defaults.string(forKey: Keys.githubRepoName) ?? ""
            return stored.isEmpty ? "workout-log" : stored
        }()
        icloudSyncEnabled = defaults.bool(forKey: Keys.icloudSyncEnabled)

        fabricEnabled = defaults.bool(forKey: Keys.fabricEnabled)
        fabricRelay = {
            let stored = defaults.string(forKey: Keys.fabricRelay) ?? ""
            return stored.isEmpty ? "wss://nip29.f7z.io" : stored
        }()
        fabricIndexerRelay = {
            let stored = defaults.string(forKey: Keys.fabricIndexerRelay) ?? ""
            return stored.isEmpty ? "wss://purplepag.es" : stored
        }()
        fabricChannel = defaults.string(forKey: Keys.fabricChannel) ?? ""
        fabricDisplayName = {
            let stored = defaults.string(forKey: Keys.fabricDisplayName) ?? ""
            return stored.isEmpty ? "coach" : stored
        }()
        fabricAbout = defaults.string(forKey: Keys.fabricAbout) ?? ""

        hasOnboarded = defaults.bool(forKey: Keys.hasOnboarded)
        doctrineEnabled = (defaults.object(forKey: Keys.doctrineEnabled) as? Bool) ?? true
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
    func providerConfig(apiKey: String?) -> ProviderConfig? {
        let key = (apiKey?.isEmpty == false) ? apiKey : nil
        switch providerKind {
        case .openRouter:
            return .openRouter(apiKey: key ?? "", baseUrl: nil)
        case .ollama:
            return .ollama(baseUrl: ollamaBaseURL, apiKey: key)
        case .appleIntelligence:
            return nil
        }
    }

    /// `.fast` is always just `fastModel`, trimmed. `.reasoning` falls back to `fastModel` when no
    /// distinct reasoning model has been chosen yet — so escalating to it is always safe (never an
    /// empty model id) even before the athlete has visited Settings → AI → Models → Reasoning.
    func model(for tier: CoachModelTier) -> String {
        switch tier {
        case .fast:
            return fastModel.trimmingCharacters(in: .whitespacesAndNewlines)
        case .reasoning:
            let trimmed = reasoningModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fastModel.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        }
    }

    func setModel(_ value: String, for tier: CoachModelTier) {
        switch tier {
        case .fast:
            fastModel = value
        case .reasoning:
            reasoningModel = value
        }
    }
}
