import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// The real Settings screen: a native grouped list (unlike Today/Runner/Coach's full-bleed
/// no-cards surfaces — this is exactly the kind of secondary, configuration-heavy screen the design
/// note calls out as correct for `List`). Reachable from a gear button on Today and on the Coach
/// screen; both share the same `AppSettings`/`CoachController` instance via `.environment`.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settingsEnv
    @Environment(CoachController.self) private var coach
    @Environment(FabricController.self) private var fabric
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settingsEnv

        NavigationStack {
            List {
                CoachAISection(settings: settings, coach: coach)
                FabricSection(settings: settings, fabric: fabric)
                SyncSection(settings: settings)
                GoalsSection(settings: settings)
                DoctrineSection(settings: settings)
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

// MARK: - Section 2: Coach fabric (tenex-edge)

/// Joins the coach to the user's tenex-edge NIP-29 fabric: an enable toggle, relay/indexer/channel
/// config, the coach's own npub (for the user to admin-add into their channel — see the footer), a
/// display name/about for the kind:0 profile, a manual "Publish profile" action, a connection status
/// indicator, and a link into the small read-only `FabricView` of recent channel traffic.
private struct FabricSection: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController

    var body: some View {
        Section {
            Toggle("Enable fabric", isOn: $settings.fabricEnabled)
                .onChange(of: settings.fabricEnabled) { _, enabled in
                    if enabled {
                        fabric.enable()
                    } else {
                        fabric.disable()
                    }
                }

            TextField("Relay(s)", text: $settings.fabricRelay, prompt: Text("wss://nip29.f7z.io"))
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Indexer relay", text: $settings.fabricIndexerRelay, prompt: Text("wss://purplepag.es"))
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Channel slug", text: $settings.fabricChannel, prompt: Text("e.g. pablo-training"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Coach display name", text: $settings.fabricDisplayName, prompt: Text("coach"))
                .textInputAutocapitalization(.never)

            TextField("About (optional)", text: $settings.fabricAbout)

            if let npub = fabric.npub {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(npub)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = npub
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copy npub")
                    }
                    Text("Add me to your channel: `tenex-edge channel add \(npub) \(settings.fabricChannel)`")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Enable the fabric to generate the coach's identity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Status", value: fabric.status.label)
            if let lastPublishError = fabric.lastPublishError {
                Text(lastPublishError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                fabric.publishProfile()
            } label: {
                Label("Publish profile", systemImage: "person.crop.circle.badge.checkmark")
            }
            .disabled(!settings.fabricEnabled)

            NavigationLink("Recent fabric messages") {
                FabricView(fabric: fabric)
            }

            #if DEBUG
            Button {
                fabric.createTestGroupForCurrentChannel()
            } label: {
                Label("Own this channel (debug/testing)", systemImage: "wrench.and.screwdriver")
            }
            .disabled(!settings.fabricEnabled || settings.fabricChannel.isEmpty)
            #endif
        } header: {
            Text("Coach fabric (tenex-edge)")
        } footer: {
            Text("Membership is admin-granted — a closed channel lets anyone read but only members can post. Run the `tenex-edge channel add` command above (from wherever you manage your tenex-edge fabric) so the coach can actually post into your channel. The nsec lives only in the Keychain — never in Settings, UserDefaults, or logs.")
        }
    }
}

// MARK: - Section 3: Sync (GitHub)

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

            Divider()

            Toggle("iCloud sync", isOn: $settings.icloudSyncEnabled)
                .onChange(of: settings.icloudSyncEnabled) { _, enabled in
                    manager.icloudToggleChanged(enabled: enabled)
                }

            LabeledContent("iCloud status", value: manager.icloudStatus.label)
            if settings.icloudSyncEnabled && !manager.isICloudAvailable {
                Text("Not signed in to iCloud, or iCloud Drive is off for this app. Sign in under the Settings app > your name > iCloud.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let lastICloudSyncedAt = manager.lastICloudSyncedAt {
                LabeledContent("iCloud last synced", value: lastICloudSyncedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Button {
                Task { await manager.pullICloudNow() }
            } label: {
                Label("Sync iCloud now", systemImage: "icloud.and.arrow.up")
            }
            .disabled(!settings.icloudSyncEnabled)
        } header: {
            Text("Sync")
        } footer: {
            Text("GitHub: paste a fine-grained or classic PAT with repo scope — sign-in-with-GitHub (device flow) needs a registered OAuth App client id and isn't wired up yet. iCloud: mirrors the same Markdown into this app's iCloud Drive container instead of (or alongside) GitHub — the two are independent and don't affect each other. Nothing here leaves the Keychain except the Markdown itself.")
        }
        .onAppear {
            token = (try? GitHubAuth.shared.currentToken()) ?? ""
        }
    }
}

// MARK: - Section 4: Goals & preferences

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

// MARK: - Section 5: Data

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

// MARK: - Section: Training doctrine (M7)

/// Lets the athlete paste in or import training doctrine — a 5/3/1 write-up, hypertrophy principles,
/// whatever they want the coach to actually use — per spec §5.7. Backed by `DoctrineStore` (its own
/// small file-persisted store, independent of SwiftData) and folded into the coach's grounding
/// context on every turn (see `CoachController.send`'s `doctrineContext`, gated by
/// `AppSettings.doctrineEnabled`).
private struct DoctrineSection: View {
    @Bindable var settings: AppSettings
    @State private var store = DoctrineStore.shared
    @State private var showingAddSheet = false
    #if DEBUG
    @State private var reviewStore = CoachReviewStore.shared
    @State private var debugDump: String?
    #endif

    var body: some View {
        Section {
            Toggle("Use doctrine in coaching", isOn: $settings.doctrineEnabled)

            if store.documents.isEmpty {
                Text("No doctrine documents yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.documents) { doc in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title)
                            .font(.subheadline.weight(.semibold))
                        Text(doc.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .onDelete { offsets in store.remove(at: offsets) }
            }

            Button {
                showingAddSheet = true
            } label: {
                Label("Add doctrine document", systemImage: "doc.badge.plus")
            }

            #if DEBUG
            // Verification-only affordances (DEBUG builds only) — let M4/M7/M2's grounding
            // assembly and the external-change review path be inspected/exercised without a real
            // GitHub repo or waiting on a sync pull. Not part of the shipped product surface.
            Divider()

            Button {
                let goals = settings.goalsContextSnippet
                let doctrine = settings.doctrineEnabled ? store.digest() : "(doctrine disabled)"
                let review = reviewStore.contextSnippet()
                let dump = """
                [goals]
                \(goals.isEmpty ? "(empty)" : goals)

                [doctrine]
                \(doctrine.isEmpty ? "(empty)" : doctrine)

                [external-change review]
                \(review.isEmpty ? "(empty)" : review)
                """
                debugDump = dump
                print("[coach-context-debug-dump]\n\(dump)")
            } label: {
                Label("Debug: dump assembled coach context", systemImage: "text.magnifyingglass")
            }

            Button {
                CoachController.shared.reviewExternalChanges([
                    GitHubSync.ChangedFile(
                        path: "sessions/2026-07-08-tuesday.md",
                        content: "# Tuesday — Upper Body\n\n## Bench Press\n- Set 1: 5x135\n- Set 2: 5x135\n- Set 3 (added drop set): 12x95, 12x75\n",
                        sha: "debug-sha",
                        commitSHA: "debug-commit",
                        commitMessage: "Add drop sets to Tuesday's bench work",
                        commitDate: .now
                    )
                ])
            } label: {
                Label("Debug: simulate external GitHub change", systemImage: "arrow.triangle.pull")
            }

            if let debugDump {
                Text(debugDump)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }

            if !reviewStore.notes.isEmpty {
                Text("Review notes (\(reviewStore.notes.count)):")
                    .font(.caption.weight(.semibold))
                ForEach(reviewStore.notes) { note in
                    Text(note.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        } header: {
            Text("Training doctrine")
        } footer: {
            Text("Paste in training notes or principles (your 5/3/1 program, hypertrophy guidelines, whatever you follow) — the coach folds a digest of these into its planning and replies.")
        }
        .sheet(isPresented: $showingAddSheet) {
            AddDoctrineSheet(store: store)
        }
    }
}

/// The "paste or file import" add flow for a single doctrine document.
private struct AddDoctrineSheet: View {
    var store: DoctrineStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var content = ""
    @State private var showingImporter = false
    @State private var importError: String?

    private var trimmedContent: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("e.g. 5/3/1 notes"))
                } header: {
                    Text("Title")
                }

                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                        .font(.footnote)
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import a text/Markdown file", systemImage: "doc.text")
                    }
                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Content")
                } footer: {
                    Text("Paste doctrine text directly, or import a .txt/.md file.")
                }
            }
            .navigationTitle("Add doctrine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.add(title: title, content: content)
                        dismiss()
                    }
                    .disabled(trimmedContent.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.plainText, .utf8PlainText, .text],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importError = nil
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                        importError = "Couldn't read that file as text."
                        return
                    }
                    content = text
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = url.deletingPathExtension().lastPathComponent
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
    }
}
