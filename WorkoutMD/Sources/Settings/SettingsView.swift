import SwiftUI
import SwiftData

/// The real Settings screen: a native grouped list (unlike Today/Runner/Coach's full-bleed
/// no-cards surfaces — this is exactly the kind of secondary, configuration-heavy screen the design
/// note calls out as correct for `List`). Reachable from a gear button on Today and on the Coach
/// screen; both share the same `AppSettings`/`CoachController` instance via `.environment`.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settingsEnv
    @Environment(CoachController.self) private var coach
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settingsEnv

        NavigationStack {
            List {
                CoachAISection(settings: settings, coach: coach)
                SyncSection(settings: settings)
                GoalsSection(settings: settings)
                DataSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Section 1: Coach / AI

private struct CoachAISection: View {
    @Bindable var settings: AppSettings
    let coach: CoachController

    @State private var openRouterKey = ""
    @State private var ollamaKey = ""
    @State private var keyStatus: String?
    @State private var ollamaModels: [String] = []
    @State private var isFetchingModels = false
    @State private var fetchModelsError: String?

    var body: some View {
        Section {
            Picker("Provider", selection: $settings.providerKind) {
                ForEach(CoachProviderKind.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.providerKind) { _, _ in coach.applySettings() }

            switch settings.providerKind {
            case .openRouter:
                SecureField("API key", text: $openRouterKey)
                    .textContentType(.password)
                    .onChange(of: openRouterKey) { _, newValue in saveOpenRouterKey(newValue) }
                if let keyStatus {
                    Text(keyStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Model", text: $settings.model, prompt: Text(settings.providerKind.modelPlaceholder))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { coach.applySettings() }

            case .ollama:
                TextField("Base URL", text: $settings.ollamaBaseURL, prompt: Text("http://localhost:11434"))
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { coach.applySettings() }

                TextField("Model", text: $settings.model, prompt: Text(settings.providerKind.modelPlaceholder))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { coach.applySettings() }

                Button {
                    Task { await fetchOllamaModels() }
                } label: {
                    HStack {
                        Text("Fetch available models")
                        Spacer()
                        if isFetchingModels { ProgressView() }
                    }
                }
                .disabled(isFetchingModels)

                if let fetchModelsError {
                    Text(fetchModelsError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !ollamaModels.isEmpty {
                    Picker("Installed models", selection: $settings.model) {
                        ForEach(ollamaModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .onChange(of: settings.model) { _, _ in coach.applySettings() }
                }

                SecureField("API key (optional, for a remote/protected Ollama)", text: $ollamaKey)
                    .onChange(of: ollamaKey) { _, newValue in saveOllamaKey(newValue) }
            }

            Picker("Coach voice", selection: $settings.verbosity) {
                ForEach(CoachVerbosity.allCases) { verbosity in
                    Text(verbosity.label).tag(verbosity)
                }
            }
            .pickerStyle(.segmented)

            DisclosureGroup("Advanced: system prompt") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $settings.systemPromptOverride)
                        .frame(minHeight: 110)
                        .font(.footnote)
                    if settings.systemPromptOverride.isEmpty {
                        Text(defaultCoachSystemPrompt())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Reset to default") { settings.systemPromptOverride = "" }
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Coach / AI")
        } footer: {
            Text("The API key never leaves the Keychain — it's not stored in preferences or logged.")
        }
        .onAppear {
            openRouterKey = (try? CoachSecrets.openRouterAPIKey()) ?? ""
            ollamaKey = (try? CoachSecrets.ollamaAPIKey()) ?? ""
        }
    }

    private func saveOpenRouterKey(_ value: String) {
        try? CoachSecrets.setOpenRouterAPIKey(value)
        keyStatus = value.isEmpty ? nil : "Key saved to Keychain."
        coach.applySettings()
    }

    private func saveOllamaKey(_ value: String) {
        try? CoachSecrets.setOllamaAPIKey(value)
        coach.applySettings()
    }

    private func fetchOllamaModels() async {
        isFetchingModels = true
        fetchModelsError = nil
        defer { isFetchingModels = false }

        guard let base = URL(string: settings.ollamaBaseURL) else {
            fetchModelsError = "Invalid base URL."
            return
        }
        let url = base.appendingPathComponent("api/tags")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            struct TagsResponse: Decodable {
                struct Model: Decodable { let name: String }
                let models: [Model]
            }
            let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
            ollamaModels = decoded.models.map(\.name).sorted()
            if settings.model.isEmpty, let first = ollamaModels.first {
                settings.model = first
            }
        } catch {
            fetchModelsError = "Could not reach Ollama at that URL."
        }
    }
}

// MARK: - Section 2: Sync (GitHub)

private struct SyncSection: View {
    @Bindable var settings: AppSettings
    @State private var manager = SyncManager.shared
    @State private var token = ""

    var body: some View {
        Section {
            SecureField("Personal access token", text: $token)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: token) { _, newValue in
                    try? GitHubAuth.shared.setToken(newValue)
                }

            TextField("Repo name", text: $settings.githubRepoName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: settings.githubRepoName) { _, newValue in
                    manager.sync.setRepoName(newValue)
                }

            LabeledContent("Status", value: manager.status.label)
            LabeledContent("Signed in", value: manager.isAuthenticated ? "Yes" : "No token")
            if let lastSyncedAt = manager.lastSyncedAt {
                LabeledContent("Last synced", value: lastSyncedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if manager.pendingCommitCount > 0 {
                LabeledContent("Pending commits", value: "\(manager.pendingCommitCount)")
            }

            Button {
                Task { await manager.pullNow() }
            } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!manager.isAuthenticated)
        } header: {
            Text("Sync (GitHub)")
        } footer: {
            Text("Paste a fine-grained or classic PAT with repo scope — sign-in-with-GitHub (device flow) needs a registered OAuth App client id and isn't wired up yet. The token lives only in the Keychain.")
        }
        .onAppear {
            token = (try? GitHubAuth.shared.currentToken()) ?? ""
        }
    }
}

// MARK: - Section 3: Goals & preferences

private struct GoalsSection: View {
    @Bindable var settings: AppSettings
    @State private var newDislikedExercise = ""

    var body: some View {
        Section {
            TextField("Primary goal", text: $settings.primaryGoal, prompt: Text("Hypertrophy"))

            Stepper(value: $settings.sessionLengthMinutes, in: 15...120, step: 5) {
                LabeledContent("Session length", value: "\(settings.sessionLengthMinutes) min")
            }

            ForEach(settings.dislikedExercises, id: \.self) { exercise in
                Text(exercise)
            }
            .onDelete { offsets in
                settings.dislikedExercises.remove(atOffsets: offsets)
            }

            HStack {
                TextField("Add a disliked exercise", text: $newDislikedExercise)
                Button("Add") {
                    let trimmed = newDislikedExercise.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !settings.dislikedExercises.contains(trimmed) else { return }
                    settings.dislikedExercises.append(trimmed)
                    newDislikedExercise = ""
                }
                .disabled(newDislikedExercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Goals & preferences")
        } footer: {
            Text("The coach sees these as grounding context — it won't program disliked exercises without asking.")
        }
    }
}

// MARK: - Section 4: Data

private struct DataSection: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]

    private var combinedMarkdown: String {
        guard !records.isEmpty else { return "# Workout.md\n\nNo sessions logged yet.\n" }
        return records.map(MarkdownGenerator.renderSession).joined(separator: "\n---\n\n")
    }

    var body: some View {
        Section {
            ShareLink(
                item: MarkdownFile(text: combinedMarkdown, filename: "workout-history.md"),
                preview: SharePreview("workout-history.md")
            ) {
                Label("Export all sessions (Markdown)", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Your workouts are plain Markdown — in this export, and in your own GitHub repo if you sign in above. Nothing here is sent anywhere except the coach provider you chose, and only the context needed for that one message.")
        }
    }
}
