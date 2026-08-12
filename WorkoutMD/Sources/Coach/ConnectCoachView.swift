import SwiftUI

/// Onboarding's in-conversation "connect a coach provider" step (fixes the old dead-end that sent
/// the athlete into the full 2400-line `SettingsView` just to start a conversation). Shown by
/// `CoachConversationView` whenever the coach isn't configured yet: a short pitch, a provider picker
/// (OpenRouter vs Ollama — mirrors `ProvidersSettingsView`'s field patterns/validation rather than
/// inventing new ones), a provider-scoped BYOK OAuth action, and manual credential entry as a
/// fallback. Both paths save the credential to Keychain, backfill a sensible default model if none
/// is set yet, re-apply the engine config, and report back via `onConnected`.
///
/// Full-bleed, no card containers — glass only on the connection actions, matching the rest of the
/// app's native-iOS look (cards read as webby on iPhone).
struct ConnectCoachView: View {
    var onConnected: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(CoachController.self) private var coach

    @State private var openRouterKey = ""
    @State private var ollamaToken = ""
    @State private var byokConnector = BYOKProviderConnector()
    @State private var isConnectingBYOK = false
    /// True while `finishConnection` is fetching a default model id after a successful key/token
    /// save — see `fetchFirstModelID`. Kept separate from `isConnectingBYOK` since it also covers the
    /// manual-connect path, which has no OAuth round trip of its own.
    @State private var isFinishingUp = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Text("Connect your coach")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Your coach runs on an AI provider you control. Connect one to build your plan.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)

                Picker("Provider", selection: Bindable(settings).providerKind) {
                    ForEach(CoachProviderKind.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.providerKind) { _, _ in
                    errorMessage = nil
                }

                if settings.providerKind.supportsBYOK {
                    byokConnectButton

                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(.white.opacity(0.14))
                            .frame(height: 1)
                        Text("or enter it manually")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize()
                        Rectangle()
                            .fill(.white.opacity(0.14))
                            .frame(height: 1)
                    }
                }

                providerFields

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                manualConnectButton
                    .padding(.top, 4)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Provider-specific fields

    @ViewBuilder
    private var providerFields: some View {
        switch settings.providerKind {
        case .openRouter:
            VStack(alignment: .leading, spacing: 6) {
                SecureField("API key", text: $openRouterKey)
                    .textContentType(.password)
                    .focused($fieldFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                Text("Stored in Keychain, never in app settings.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }

        case .ollama:
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Base URL", text: Bindable(settings).ollamaBaseURL,
                        prompt: Text("http://localhost:11434").foregroundStyle(.white.opacity(0.35))
                    )
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .focused($fieldFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
                    Text("A real iPhone can't reach a Mac's localhost — use a reachable LAN or remote URL.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                SecureField("API token (optional)", text: $ollamaToken)
                    .focused($fieldFocused)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }

        case .appleIntelligence:
            let availability = AppleIntelligenceCoachProvider().availability
            VStack(spacing: 10) {
                Image(systemName: availability.isAvailable ? "apple.intelligence" : "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                Text(availability.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: Connect

    private var byokConnectButton: some View {
        Button {
            Task { await connectWithBYOK() }
        } label: {
            HStack(spacing: 9) {
                if isConnectingBYOK {
                    ProgressView()
                } else {
                    Image(systemName: "link.badge.plus")
                }
                Text(isConnectingBYOK ? "Opening BYOK…" : "Connect with BYOK")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.glassProminent)
        .tint(.indigo)
        .disabled(isConnectingBYOK || isFinishingUp || !canConnectWithBYOK)
        .accessibilityHint("Opens BYOK to choose a \(settings.providerKind.label) key securely.")
    }

    private var manualConnectButton: some View {
        Button {
            Task { await connectManually() }
        } label: {
            Text(manualButtonTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(.glass)
        .disabled(isConnectingBYOK || isFinishingUp || !canConnectManually)
    }

    private var manualButtonTitle: String {
        if isFinishingUp { return "Connecting…" }
        return settings.providerKind == .appleIntelligence ? "Use Apple Intelligence" : "Connect Manually"
    }

    private var canConnectWithBYOK: Bool {
        switch settings.providerKind {
        case .openRouter:
            return true
        case .ollama:
            return !settings.ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .appleIntelligence:
            return false
        }
    }

    private var canConnectManually: Bool {
        switch settings.providerKind {
        case .openRouter:
            return !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .ollama:
            return !settings.ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .appleIntelligence:
            return AppleIntelligenceCoachProvider().availability.isAvailable
        }
    }

    /// Saves whichever credential the selected provider needs, then hands off to `finishConnection`,
    /// which fetches (never hardcodes) a default model if none is set yet.
    private func connectManually() async {
        errorMessage = nil
        fieldFocused = false

        switch settings.providerKind {
        case .openRouter:
            let trimmed = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            do {
                try CoachSecrets.setOpenRouterAPIKey(trimmed)
            } catch {
                errorMessage = "Couldn't save the key: \(error.localizedDescription)"
                return
            }

        case .ollama:
            let token = ollamaToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                do {
                    try CoachSecrets.setOllamaAPIKey(token)
                } catch {
                    errorMessage = "Couldn't save the token: \(error.localizedDescription)"
                    return
                }
            }
        case .appleIntelligence:
            break
        }

        await finishConnection(provider: settings.providerKind)
    }

    /// Requests only the currently selected provider scope. BYOK returns a short-lived code via the
    /// app callback; `BYOKProviderConnector` verifies state + PKCE and exchanges it for the selected
    /// raw key, which moves directly into Keychain and is never logged or persisted in view state.
    private func connectWithBYOK() async {
        errorMessage = nil
        fieldFocused = false
        isConnectingBYOK = true
        defer { isConnectingBYOK = false }

        let requestedProvider = settings.providerKind
        do {
            let grants = try await byokConnector.connect(providers: [requestedProvider])
            guard let grant = grants.first(where: { $0.provider == requestedProvider }) else {
                errorMessage = "BYOK didn't return the selected provider."
                return
            }
            _ = try CoachSecrets.saveBYOKGrant(grant)
            await finishConnection(provider: grant.provider)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// If no fast-tier model is set yet, fetches that provider's real catalog and picks the first
    /// result — a fetched default, never a hardcoded model id. `AppSettings.model(for:.reasoning)`
    /// already falls back to `fastModel` when its own field is empty, so setting this one field
    /// alone is enough to unblock every turn, at both tiers. If the fetch fails (or returns
    /// nothing), `settings.fastModel` is simply left unset — the athlete picks explicitly in
    /// `ModelSelectorView` (Settings → AI → Models) instead of getting a silent guess.
    private func finishConnection(provider: CoachProviderKind) async {
        settings.providerKind = provider

        if provider.usesModelPicker,
           settings.fastModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isFinishingUp = true
            if let firstModelID = await fetchFirstModelID(for: provider) {
                settings.fastModel = firstModelID
            }
            isFinishingUp = false
        }

        coach.applySettings()
        Haptics.success()
        onConnected()
    }

    private func fetchFirstModelID(for provider: CoachProviderKind) async -> String? {
        let source: ModelCatalogSource
        switch provider {
        case .openRouter:
            source = .openRouter
        case .ollama:
            source = .ollama(baseURL: settings.ollamaBaseURL)
        case .appleIntelligence:
            return nil
        }
        let models = try? await ModelCatalogService().fetchModels(source: source)
        return models?.first?.id
    }
}
