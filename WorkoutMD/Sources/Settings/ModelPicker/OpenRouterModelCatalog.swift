import Foundation

/// Ported from RockingLife's `OpenRouterModelCatalog.swift` (win-the-day-app) to give per-role model
/// selection (`ModelTierSettingsView`) a real, fetched, searchable model navigator instead of a
/// hardcoded suggestions list — for BOTH providers this app supports. `ModelCatalogSource` decides
/// what gets fetched: the public OpenRouter catalog, or a local Ollama server's `/api/tags`. Neither
/// path ever falls back to a hardcoded model id — a fetch failure just means an empty list plus an
/// error the athlete can retry, and the custom-id field remains available either way.
///
/// Deliberately capability/date-free: no tool/reasoning/vision/open-weights/moderation flags, no
/// created/release/updated dates anywhere in this model — just identity (id/name/maker) and pricing
/// + context limits, which is all `ModelSelectorView`'s rows/detail sheet show.
struct ModelCatalogService: Sendable {
    func fetchModels(source: ModelCatalogSource) async throws -> [ModelCatalogOption] {
        switch source {
        case .openRouter:
            return try await fetchOpenRouterCatalog()
        case .ollama(let baseURL):
            return try await fetchOllamaCatalog(baseURL: baseURL)
        }
    }

    // MARK: OpenRouter

    private func fetchOpenRouterCatalog() async throws -> [ModelCatalogOption] {
        async let openRouter = fetchOpenRouterModels()
        async let modelsDev = fetchModelsDevCatalogOptional()

        let models = try await openRouter
        let metadata = await modelsDev

        return models
            .map { ModelCatalogOption(openRouter: $0, modelsDev: metadata) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The `GET /models` catalog is public — no `Authorization` header needed, only the cosmetic
    /// `X-Title` OpenRouter uses for its own dashboards.
    private func fetchOpenRouterModels() async throws -> [OpenRouterModel] {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        request.setValue("Workout.md", forHTTPHeaderField: "X-Title")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ModelCatalogError.requestFailed(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data).data
        } catch {
            throw ModelCatalogError.decoding("OpenRouter models: \(error.localizedDescription)")
        }
    }

    /// Best-effort only: any failure (network, decode) returns `nil` rather than throwing, so the
    /// OpenRouter catalog still works on OpenRouter's own data alone. Only used for provider display
    /// names and a pricing/context fallback now — no capability or date fields survive the mapping.
    private func fetchModelsDevCatalogOptional() async -> ModelsDevCatalog? {
        do {
            var request = URLRequest(url: URL(string: "https://models.dev/api.json")!)
            request.cachePolicy = .reloadRevalidatingCacheData
            let (data, _) = try await URLSession.shared.data(for: request)
            let providers = try JSONDecoder().decode([String: ModelsDevProvider].self, from: data)
            return ModelsDevCatalog(providers: providers)
        } catch {
            return nil
        }
    }

    // MARK: Ollama

    /// Fetches the athlete's own local server's installed models — `GET {baseURL}/api/tags` — rather
    /// than any hardcoded list, so this only ever shows models actually pulled on that machine.
    private func fetchOllamaCatalog(baseURL: String) async throws -> [ModelCatalogOption] {
        guard let base = URL(string: baseURL), let url = URL(string: "api/tags", relativeTo: base) else {
            throw ModelCatalogError.invalidBaseURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ModelCatalogError.requestFailed(http.statusCode)
        }
        let decoded: OllamaTagsResponse
        do {
            decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        } catch {
            throw ModelCatalogError.decoding("Ollama models: \(error.localizedDescription)")
        }
        return decoded.models
            .map { ModelCatalogOption(ollama: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension ModelCatalogService {
    /// Test seam: runs the exact decode + `ModelCatalogOption` mapping `fetchModels(source: .openRouter)`
    /// uses, against in-memory JSON — no network. `OpenRouterModelsResponse`/`ModelsDevProvider` are
    /// file-private, so this lives here rather than being reconstructed in the test target.
    static func decode(openRouterJSON: Data, modelsDevJSON: Data? = nil) throws -> [ModelCatalogOption] {
        let models = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: openRouterJSON).data
        let metadata: ModelsDevCatalog? = modelsDevJSON.flatMap { data in
            (try? JSONDecoder().decode([String: ModelsDevProvider].self, from: data)).map(ModelsDevCatalog.init)
        }
        return models.map { ModelCatalogOption(openRouter: $0, modelsDev: metadata) }
    }
}

/// Which catalog `ModelSelectorView`/`ModelCatalogService` fetch from — the one axis that varies
/// between the two providers this app supports. `ModelSelectorView` is otherwise identical for both.
enum ModelCatalogSource: Hashable {
    case openRouter
    case ollama(baseURL: String)

    var title: String {
        switch self {
        case .openRouter: return "OpenRouter Models"
        case .ollama: return "Ollama Models"
        }
    }
}

enum ModelCatalogError: LocalizedError {
    case requestFailed(Int)
    case decoding(String)
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status):
            return "Models request failed (status \(status))."
        case .decoding(let message):
            return message
        case .invalidBaseURL:
            return "Invalid server URL."
        }
    }
}

/// Unified view model over a catalog entry from either provider. `id` is what actually gets written
/// to `AppSettings` (the real model id/name the engine calls with); everything else is display-only.
struct ModelCatalogOption: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var providerID: String
    var providerName: String
    var modelDescription: String?
    var promptCostPerMillion: Double?
    var completionCostPerMillion: Double?
    var cacheReadCostPerMillion: Double?
    var cacheWriteCostPerMillion: Double?
    var contextLength: Int?
    var outputLimit: Int?

    fileprivate init(openRouter model: OpenRouterModel, modelsDev: ModelsDevCatalog?) {
        let devModel = modelsDev?.openRouterModel(id: model.id)
        let providerID = Self.providerID(from: model.id)
        let provider = modelsDev?.provider(id: providerID)

        self.id = model.id
        self.name = model.name
        self.providerID = providerID
        self.providerName = Self.providerName(from: model.name, provider: provider, providerID: providerID)
        self.modelDescription = model.description
        self.promptCostPerMillion = model.pricing?.prompt?.costPerMillion ?? devModel?.cost?.input
        self.completionCostPerMillion = model.pricing?.completion?.costPerMillion ?? devModel?.cost?.output
        self.cacheReadCostPerMillion = model.pricing?.inputCacheRead?.costPerMillion ?? devModel?.cost?.cacheRead
        self.cacheWriteCostPerMillion = model.pricing?.inputCacheWrite?.costPerMillion ?? devModel?.cost?.cacheWrite
        self.contextLength = model.contextLength ?? model.topProvider?.contextLength ?? devModel?.limit?.context
        self.outputLimit = model.topProvider?.maxCompletionTokens ?? devModel?.limit?.output
    }

    /// Ollama has no pricing/context metadata over `/api/tags` — this is identity only. The maker is
    /// derived from the name (e.g. "llama3.1:8b" → "llama") purely for the logo/initials and provider
    /// filter; it's never a real models.dev provider id, so `logoURL` will 404 and `ProviderLogoView`
    /// falls back to initials, which is the intended behavior for local models.
    fileprivate init(ollama model: OllamaTagModel) {
        let providerID = Self.ollamaProviderID(from: model.name)
        self.id = model.name
        self.name = model.name
        self.providerID = providerID
        self.providerName = providerID.capitalized
        self.modelDescription = nil
        self.promptCostPerMillion = nil
        self.completionCostPerMillion = nil
        self.cacheReadCostPerMillion = nil
        self.cacheWriteCostPerMillion = nil
        self.contextLength = nil
        self.outputLimit = nil
    }

    var logoURL: URL {
        URL(string: "https://models.dev/logos/\(providerID).svg")!
    }

    var isFree: Bool {
        promptCostPerMillion == 0 && completionCostPerMillion == 0
    }

    var compactPricing: String {
        guard let input = promptCostPerMillion, let output = completionCostPerMillion else {
            return "Variable"
        }
        if input == 0 && output == 0 {
            return "Free"
        }
        return "\(Self.money(input)) in / \(Self.money(output)) out"
    }

    var searchText: String {
        [id, name, providerName, providerID, modelDescription ?? ""]
            .joined(separator: " ")
            .lowercased()
    }

    private static func providerID(from modelID: String) -> String {
        modelID.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "openrouter"
    }

    private static func providerName(from modelName: String, provider: ModelsDevProvider?, providerID: String) -> String {
        if let provider { return provider.name }
        if let colon = modelName.firstIndex(of: ":") {
            return String(modelName[..<colon])
        }
        return providerID
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    /// The maker prefix before the first `:` or `/`, with a trailing version number (digits/dots)
    /// stripped — e.g. "llama3.1:8b" → "llama3.1" → "llama", "mistral" → "mistral".
    private static func ollamaProviderID(from modelName: String) -> String {
        let beforeColon = modelName.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? modelName
        let beforeSlash = beforeColon.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? beforeColon

        var characters = Array(beforeSlash)
        while let last = characters.last, last.isNumber || last == "." {
            characters.removeLast()
        }
        let trimmed = String(characters)
        return (trimmed.isEmpty ? beforeSlash : trimmed).lowercased()
    }

    static func money(_ value: Double) -> String {
        if value == 0 { return "$0" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        if value < 1 { return String(format: "$%.2f", value) }
        if value.rounded() == value { return String(format: "$%.0f", value) }
        return String(format: "$%.2f", value)
    }

    static func perToken(_ value: Double?) -> String {
        guard let value else { return "Variable" }
        let token = value / 1_000_000
        if token == 0 { return "$0/token" }
        return String(format: "$%.9f/token", token)
    }
}

// MARK: - OpenRouter wire format

private struct OpenRouterModelsResponse: Decodable, Sendable {
    var data: [OpenRouterModel]
}

private struct OpenRouterModel: Decodable, Sendable {
    var id: String
    var name: String
    var description: String?
    var contextLength: Int?
    var pricing: OpenRouterPricing?
    var topProvider: OpenRouterTopProvider?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case contextLength = "context_length"
        case pricing
        case topProvider = "top_provider"
    }
}

private struct OpenRouterPricing: Decodable, Sendable {
    var prompt: String?
    var completion: String?
    var inputCacheRead: String?
    var inputCacheWrite: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case completion
        case inputCacheRead = "input_cache_read"
        case inputCacheWrite = "input_cache_write"
    }
}

private struct OpenRouterTopProvider: Decodable, Sendable {
    var contextLength: Int?
    var maxCompletionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case contextLength = "context_length"
        case maxCompletionTokens = "max_completion_tokens"
    }
}

// MARK: - Ollama wire format

private struct OllamaTagsResponse: Decodable, Sendable {
    var models: [OllamaTagModel]
}

private struct OllamaTagModel: Decodable, Sendable {
    var name: String
}

// MARK: - models.dev enrichment (OpenRouter only)

private struct ModelsDevCatalog: Sendable {
    var providers: [String: ModelsDevProvider]

    func provider(id: String) -> ModelsDevProvider? {
        providers[id]
    }

    func openRouterModel(id: String) -> ModelsDevModel? {
        providers["openrouter"]?.models[id]
    }
}

private struct ModelsDevProvider: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var models: [String: ModelsDevModel]
}

private struct ModelsDevModel: Decodable, Hashable, Sendable {
    var id: String
    var name: String
    var cost: ModelsDevCost?
    var limit: ModelsDevLimit?
}

private struct ModelsDevCost: Decodable, Hashable, Sendable {
    var input: Double?
    var output: Double?
    var cacheRead: Double?
    var cacheWrite: Double?

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }
}

private struct ModelsDevLimit: Decodable, Hashable, Sendable {
    var context: Int?
    var output: Int?
}

private extension String {
    /// Prices in the OpenRouter API are strings in $/token; the UI wants $/million.
    var costPerMillion: Double? {
        guard let value = Double(self), value >= 0 else { return nil }
        return value * 1_000_000
    }
}
