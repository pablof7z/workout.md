import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// A native Settings-style hierarchy. The root is a directory of domains; detailed controls live one
/// push deeper so Today/Coach no longer open a crowded all-in-one configuration sheet.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settingsEnv
    @Environment(CoachController.self) private var coach
    @Environment(FabricController.self) private var fabric
    @Environment(\.dismiss) private var dismiss

    /// Whether the coach is actually usable — an OpenRouter key is stored, or Ollama (a deliberate
    /// local choice) is selected. Mirrors `CoachView`/`CoachConversationView.isCoachConfigured`.
    /// This is what the Coach row's status badge reflects — NOT the optional tenex-edge fabric
    /// connection (which is only one of the four things behind that row and lives in its detail).
    private var coachStatusLabel: String {
        switch settingsEnv.providerKind {
        case .openRouter:
            let key = (try? CoachSecrets.openRouterAPIKey()) ?? nil
            return (key ?? "").isEmpty ? "Not set up" : "Ready"
        case .ollama:
            return "Ready"
        case .appleIntelligence:
            return AppleIntelligenceCoachProvider().availability.statusLabel
        }
    }

    var body: some View {
        @Bindable var settings = settingsEnv

        NavigationStack {
            List {
                Section {
                    SettingsNavigationRow(
                        title: "Coach",
                        subtitle: "Profile, prompt, doctrine, tenex-edge",
                        value: coachStatusLabel,
                        systemImage: "figure.strengthtraining.traditional",
                        destination: CoachSettingsView(settings: settings, coach: coach, fabric: fabric)
                    )
                    SettingsNavigationRow(
                        title: "AI",
                        subtitle: "Providers, models, context privacy",
                        value: settings.providerKind.label,
                        systemImage: "sparkles",
                        destination: AISettingsView(settings: settings, coach: coach)
                    )
                    SettingsNavigationRow(
                        title: "Workout",
                        subtitle: "Capture, deviations, plan repair",
                        value: "Capture",
                        systemImage: "list.clipboard",
                        destination: WorkoutSettingsView(settings: settings)
                    )
                    SettingsNavigationRow(
                        title: "Data",
                        subtitle: "Integrations, sync, Markdown, backups",
                        value: SyncManager.shared.isAuthenticated ? "GitHub" : "Local",
                        systemImage: "externaldrive",
                        destination: DataSettingsView(settings: settings)
                    )
                    SettingsNavigationRow(
                        title: "Advanced",
                        subtitle: "Diagnostics and destructive controls",
                        value: "Debug",
                        systemImage: "gearshape.2",
                        destination: AdvancedSettingsView(settings: settings, fabric: fabric)
                    )
                } header: {
                    Text("Workout.md")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Root rows

private struct SettingsNavigationRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let value: String
    let systemImage: String
    let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                SettingsIcon(systemImage: systemImage)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SettingsIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        LabeledContent {
            Text(value)
                .font(monospaced ? .caption.monospaced() : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } label: {
            Text(title)
        }
    }
}

private extension FabricConnectionStatus {
    var compactLabel: String {
        switch self {
        case .disconnected: return "Off"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
}

// MARK: - Coach

private struct CoachSettingsView: View {
    @Bindable var settings: AppSettings
    let coach: CoachController
    let fabric: FabricController

    var body: some View {
        List {
            Section {
                SettingsNavigationRow(
                    title: "Profile",
                    subtitle: "Name, about, avatar, npub",
                    value: settings.fabricDisplayName,
                    systemImage: "person.crop.circle",
                    destination: CoachProfileSettingsView(settings: settings, fabric: fabric)
                )
                SettingsNavigationRow(
                    title: "System Prompt",
                    subtitle: "Default prompt, override, voice",
                    value: settings.verbosity.label,
                    systemImage: "text.quote",
                    destination: SystemPromptSettingsView(settings: settings)
                )
                SettingsNavigationRow(
                    title: "Behavior / Authority",
                    subtitle: "Suggest-only, auto-apply, plan edits",
                    value: "Ask first",
                    systemImage: "hand.raised",
                    destination: CoachPolicySettingsView()
                )
                SettingsNavigationRow(
                    title: "Training Doctrine",
                    subtitle: "Uploaded principles and methods",
                    value: settings.doctrineEnabled ? "On" : "Off",
                    systemImage: "doc.text",
                    destination: DoctrineSettingsView(settings: settings)
                )
                SettingsNavigationRow(
                    title: "Coach Memory",
                    subtitle: "Transcript memory and context windows",
                    value: "60 days",
                    systemImage: "brain",
                    destination: CoachMemorySettingsView()
                )
                SettingsNavigationRow(
                    title: "tenex-edge",
                    subtitle: "Channels, relays, membership, traffic",
                    value: settings.fabricChannel.isEmpty ? "No channel" : settings.fabricChannel,
                    systemImage: "network",
                    destination: TenexEdgeSettingsView(settings: settings, fabric: fabric)
                )
            }
        }
        .navigationTitle("Coach")
    }
}

private struct CoachProfileSettingsView: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController

    @State private var avatarURL = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.square")
                        .font(.system(size: 36))
                        .frame(width: 72, height: 72)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(settings.fabricDisplayName)
                            .font(.headline)
                        Text(fabric.npub ?? "Enable fabric to generate identity")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TextField("Name", text: $settings.fabricDisplayName, prompt: Text("coach"))
                    .textInputAutocapitalization(.never)
                TextField("About", text: $settings.fabricAbout, prompt: Text("Dry strength coach for Workout.md"))
                TextField("Avatar URL", text: $avatarURL, prompt: Text("https://..."))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Picture publishing is reserved for the fabric profile surface; the current Rust API already supports the field.")
            }

            Section {
                if let npub = fabric.npub {
                    SettingsValueRow(title: "npub", value: npub, monospaced: true)
                    Button {
                        UIPasteboard.general.string = npub
                    } label: {
                        Label("Copy npub", systemImage: "doc.on.doc")
                    }
                } else {
                    Text("No fabric identity yet.")
                        .foregroundStyle(.secondary)
                }
                Button {
                    fabric.publishProfile()
                } label: {
                    Label("Publish Profile", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(!settings.fabricEnabled)
            } footer: {
                Text("The nsec stays in Keychain. Import, export, and rotation should require explicit confirmation before writing secrets.")
            }

            Section {
                Button(role: .destructive) {
                    // Placeholder until identity rotation is implemented against the Keychain and engine.
                } label: {
                    Label("Reset / Rotate Identity", systemImage: "arrow.clockwise")
                }
                .disabled(true)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SystemPromptSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Coach voice", selection: $settings.verbosity) {
                    ForEach(CoachVerbosity.allCases) { verbosity in
                        Text(verbosity.label).tag(verbosity)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextEditor(text: $settings.systemPromptOverride)
                    .frame(minHeight: 220)
                    .font(.body.monospaced())
                if settings.systemPromptOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(defaultCoachSystemPrompt())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Reset to default") {
                        settings.systemPromptOverride = ""
                    }
                }
            } header: {
                Text("Custom Override")
            } footer: {
                Text("Empty means the Rust default coach prompt is used, then the selected voice is appended.")
            }

            Section("Effective Voice Suffix") {
                Text(settings.verbosity.promptSuffix.isEmpty ? "Default balanced voice." : settings.verbosity.promptSuffix)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("System Prompt")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CoachPolicySettingsView: View {
    @AppStorage("settings.coach.policy.mode") private var policyMode = "Ask First"
    @AppStorage("settings.coach.policy.adjustRemainingSets") private var adjustRemainingSets = true
    @AppStorage("settings.coach.policy.substitutions") private var substitutions = false
    @AppStorage("settings.coach.policy.futurePlanEdits") private var futurePlanEdits = false
    @AppStorage("settings.coach.policy.deloads") private var deloads = true
    @AppStorage("settings.coach.policy.recoveryChanges") private var recoveryChanges = false

    var body: some View {
        Form {
            Section {
                Picker("Default authority", selection: $policyMode) {
                    Text("Suggest").tag("Suggest")
                    Text("Ask First").tag("Ask First")
                    Text("Auto").tag("Auto")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("These settings define the envelope the coach should operate inside. Tool enforcement can be tightened as policy support expands.")
            }

            Section("Allowed Changes") {
                Toggle("Adjust remaining sets", isOn: $adjustRemainingSets)
                Toggle("Substitute exercises", isOn: $substitutions)
                Toggle("Edit future plan", isOn: $futurePlanEdits)
                Toggle("Recommend deloads", isOn: $deloads)
                Toggle("Auto-apply recovery changes", isOn: $recoveryChanges)
            }
        }
        .navigationTitle("Behavior")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DoctrineSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var store = DoctrineStore.shared
    @State private var showingAddSheet = false
    #if DEBUG
    @State private var reviewStore = CoachReviewStore.shared
    @State private var debugDump: String?
    @Environment(\.modelContext) private var modelContext
    #endif

    var body: some View {
        List {
            Section {
                Toggle("Use doctrine in coaching", isOn: $settings.doctrineEnabled)
            } footer: {
                Text("The coach folds a bounded digest of these documents into planning and replies.")
            }

            Section {
                if store.documents.isEmpty {
                    Text("No doctrine documents yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.documents) { doc in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(doc.title)
                                .font(.headline)
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
                    Label("Add Doctrine Document", systemImage: "doc.badge.plus")
                }
            } header: {
                Text("Documents")
            }

            #if DEBUG
            Section("Debug") {
                Button {
                    let memory = MemoryStore(context: modelContext).digest()
                    let doctrine = settings.doctrineEnabled ? store.digest() : "(doctrine disabled)"
                    let review = reviewStore.contextSnippet()
                    let dump = """
                    [memory]
                    \(memory.isEmpty ? "(empty)" : memory)

                    [doctrine]
                    \(doctrine.isEmpty ? "(empty)" : doctrine)

                    [external-change review]
                    \(review.isEmpty ? "(empty)" : review)
                    """
                    debugDump = dump
                    print("[coach-context-debug-dump]\n\(dump)")
                } label: {
                    Label("Dump Assembled Coach Context", systemImage: "text.magnifyingglass")
                }

                Button {
                    CoachController.shared.reviewExternalChanges([
                        GitHubSync.ChangedFile(
                            path: "sessions/2026-07-08-tuesday.md",
                            content: "# Tuesday - Upper Body\n\n## Bench Press\n- Set 1: 5x135\n- Set 2: 5x135\n- Set 3 (added drop set): 12x95, 12x75\n",
                            sha: "debug-sha",
                            commitSHA: "debug-commit",
                            commitMessage: "Add drop sets to Tuesday's bench work",
                            commitDate: .now
                        )
                    ])
                } label: {
                    Label("Simulate External GitHub Change", systemImage: "arrow.triangle.pull")
                }

                if let debugDump {
                    Text(debugDump)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                }
            }
            #endif
        }
        .navigationTitle("Doctrine")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddSheet) {
            AddDoctrineSheet(store: store)
        }
    }
}

/// General durable memory (domain-primitives.md §5) is user-visible/editable here: a freeform
/// list of `MemoryRecord`s — add, inline-edit, swipe-to-delete — backed directly by `@Query` and
/// `MemoryStore`, so this list IS the coach's memory rather than a separate view of it. Kept
/// distinct from the transcript-memory policy controls below (`CoachNoteRecord`'s recency window
/// and which context blocks get folded in) — a different, older concept (domain-primitives.md
/// §5's "distinct concepts" list).
private struct CoachMemorySettingsView: View {
    @AppStorage("settings.coach.memory.includeTranscript") private var includeTranscript = true
    @AppStorage("settings.coach.memory.includeReviews") private var includeReviews = true
    @AppStorage("settings.coach.memory.includeFabric") private var includeFabric = true
    @AppStorage("settings.coach.memory.longTerm") private var longTerm = false
    @AppStorage("settings.coach.memory.recencyDays") private var recencyDays = 60

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryRecord.updatedAt, order: .reverse) private var memories: [MemoryRecord]
    @State private var newMemoryText = ""

    private var store: MemoryStore { MemoryStore(context: modelContext) }

    var body: some View {
        Form {
            Section {
                TextField(
                    "New memory", text: $newMemoryText,
                    prompt: Text("e.g. Prefers training in the evening"), axis: .vertical
                )
                Button {
                    addMemory()
                } label: {
                    Label("Add Memory", systemImage: "plus.circle")
                }
                .disabled(newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Add a Memory")
            } footer: {
                Text("Freeform durable notes about the athlete — goals, preferences, injuries, anything worth the coach remembering. Folded into every coach turn's context.")
            }

            Section {
                if memories.isEmpty {
                    Text("No memories yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(memories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Memory", text: textBinding(for: memory), axis: .vertical)
                            if !memory.tags.isEmpty {
                                Text(memory.tags.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.remove(id: memory.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("Memories")
            }

            Section {
                Stepper(value: $recencyDays, in: 7...365, step: 7) {
                    LabeledContent("Transcript recency window", value: "\(recencyDays) days")
                }
                Toggle("Coach transcript memory", isOn: $includeTranscript)
                Toggle("External sync review notes", isOn: $includeReviews)
                Toggle("Recent tenex-edge messages", isOn: $includeFabric)
                Toggle("Long-term history", isOn: $longTerm)
            } footer: {
                Text("The current runtime uses a 60-day exercise-scoped transcript memory window (separate from the durable memories above). These settings make the policy visible for the next enforcement pass.")
            }

            Section {
                Button(role: .destructive) {
                    // Future: delete CoachNoteRecord rows after confirmation.
                } label: {
                    Label("Clear Coach Transcript Memory", systemImage: "trash")
                }
                .disabled(true)
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addMemory() {
        let trimmed = newMemoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(text: trimmed, source: "user")
        newMemoryText = ""
    }

    private func textBinding(for memory: MemoryRecord) -> Binding<String> {
        Binding(
            get: { memory.text },
            set: { store.update(id: memory.id, text: $0) }
        )
    }
}

// MARK: - tenex-edge

private struct TenexEdgeSettingsView: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController

    var body: some View {
        List {
            Section {
                Toggle("Enable fabric", isOn: $settings.fabricEnabled)
                    .onChange(of: settings.fabricEnabled) { _, enabled in
                        if enabled {
                            fabric.enable()
                        } else {
                            fabric.disable()
                        }
                    }
                SettingsValueRow(title: "Status", value: fabric.status.label)
                if let lastPublishError = fabric.lastPublishError {
                    Text(lastPublishError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                SettingsNavigationRow(
                    title: "Profile",
                    subtitle: "Kind:0 name, about, npub",
                    value: settings.fabricDisplayName,
                    systemImage: "person.text.rectangle",
                    destination: FabricProfileSettingsView(settings: settings, fabric: fabric)
                )
                SettingsNavigationRow(
                    title: "Channels",
                    subtitle: "Active channel and channel list",
                    value: settings.fabricChannel.isEmpty ? "Unset" : settings.fabricChannel,
                    systemImage: "number",
                    destination: FabricChannelsSettingsView(settings: settings)
                )
                SettingsNavigationRow(
                    title: "Relays",
                    subtitle: "Main relays and profile indexer",
                    value: "\(settings.fabricRelaysList.count)",
                    systemImage: "antenna.radiowaves.left.and.right",
                    destination: FabricRelaysSettingsView(settings: settings)
                )
                SettingsNavigationRow(
                    title: "Membership",
                    subtitle: "Join request and admin-granted status",
                    value: fabric.npub == nil ? "No identity" : "Ready",
                    systemImage: "person.2.badge.gearshape",
                    destination: FabricMembershipSettingsView(settings: settings, fabric: fabric)
                )
            } header: {
                Text("Connection")
            }

            Section {
                SettingsNavigationRow(
                    title: "Subscriptions",
                    subtitle: "Whole channel, mentions, event kinds",
                    value: "Whole",
                    systemImage: "dot.radiowaves.left.and.right",
                    destination: FabricSubscriptionsSettingsView()
                )
                SettingsNavigationRow(
                    title: "Publishing Scope",
                    subtitle: "What the coach posts externally",
                    value: "Summaries",
                    systemImage: "paperplane",
                    destination: FabricPublishingSettingsView()
                )
                SettingsNavigationRow(
                    title: "Recent Traffic",
                    subtitle: "Messages, status, roster, proposals",
                    value: "\(fabric.messages.count)",
                    systemImage: "bubble.left.and.text.bubble.right",
                    destination: FabricView(fabric: fabric)
                )
            } header: {
                Text("Runtime")
            }
        }
        .navigationTitle("tenex-edge")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FabricProfileSettingsView: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController

    var body: some View {
        Form {
            Section {
                TextField("Display name", text: $settings.fabricDisplayName, prompt: Text("coach"))
                    .textInputAutocapitalization(.never)
                TextField("About", text: $settings.fabricAbout)
                if let npub = fabric.npub {
                    SettingsValueRow(title: "npub", value: npub, monospaced: true)
                    Button {
                        UIPasteboard.general.string = npub
                    } label: {
                        Label("Copy npub", systemImage: "doc.on.doc")
                    }
                } else {
                    Text("Enable fabric to generate the coach identity.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    fabric.publishProfile()
                } label: {
                    Label("Publish Profile", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(!settings.fabricEnabled)
            }
        }
        .navigationTitle("Fabric Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FabricChannelsSettingsView: View {
    @Bindable var settings: AppSettings
    @AppStorage("settings.fabric.savedChannels") private var savedChannels = "pablo-training\ncoach-lab"

    private var channels: [String] {
        savedChannels
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Section {
                TextField("Active channel slug", text: $settings.fabricChannel, prompt: Text("pablo-training"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ForEach(channels, id: \.self) { channel in
                    Button {
                        settings.fabricChannel = channel
                    } label: {
                        HStack {
                            Text(channel)
                            Spacer()
                            if channel == settings.fabricChannel {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Channels")
            } footer: {
                Text("Discovery and metadata need the next fabric pass; this screen gives the current single-channel setting a native home.")
            }

            Section("Saved Channels") {
                TextEditor(text: $savedChannels)
                    .frame(minHeight: 120)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FabricRelaysSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.fabricRelay)
                    .frame(minHeight: 120)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ForEach(settings.fabricRelaysList, id: \.self) { relay in
                    SettingsValueRow(title: relay, value: "Read/write")
                }
            } header: {
                Text("Main Relays")
            } footer: {
                Text("Enter one relay per line or separate with commas. Per-relay health and flags can build on this persisted representation.")
            }

            Section("Profile Indexer") {
                TextField("Indexer relay", text: $settings.fabricIndexerRelay, prompt: Text("wss://purplepag.es"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
            }
        }
        .navigationTitle("Relays")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FabricMembershipSettingsView: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController

    @State private var joinInviteCode = ""

    private var adminCommand: String {
        guard let npub = fabric.npub, !settings.fabricChannel.isEmpty else { return "" }
        return "tenex-edge channel add \(npub) \(settings.fabricChannel)"
    }

    var body: some View {
        Form {
            Section {
                SettingsValueRow(title: "Channel", value: settings.fabricChannel.isEmpty ? "Unset" : settings.fabricChannel)
                SettingsValueRow(title: "Identity", value: fabric.npub ?? "No identity", monospaced: fabric.npub != nil)
                SettingsValueRow(title: "Membership", value: fabric.npub == nil ? "Not ready" : "Admin-granted")
            }

            Section {
                if adminCommand.isEmpty {
                    Text("Set a channel and enable fabric to generate the admin command.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(adminCommand)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = adminCommand
                    } label: {
                        Label("Copy Admin Command", systemImage: "doc.on.doc")
                    }
                }
            } footer: {
                Text("Admin-granted membership is the most reliable path for closed channels.")
            }

            Section {
                TextField("Invite code (optional)", text: $joinInviteCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    fabric.requestToJoin(inviteCode: joinInviteCode)
                } label: {
                    Label("Request to Join", systemImage: "person.badge.plus")
                }
                .disabled(settings.fabricChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let lastJoinRequestResult = fabric.lastJoinRequestResult {
                    Text(lastJoinRequestResult)
                        .font(.caption)
                        .foregroundStyle(lastJoinRequestResult.hasPrefix("Join request sent") ? Color.secondary : Color.orange)
                }
            } footer: {
                Text("Sends a standard NIP-29 join request. An admin still needs to approve it unless the relay auto-approves open channels.")
            }
        }
        .navigationTitle("Membership")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FabricSubscriptionsSettingsView: View {
    @AppStorage("settings.fabric.subscription.mode") private var subscriptionMode = "Whole Channel"
    @AppStorage("settings.fabric.subscribe.chat") private var chat = true
    @AppStorage("settings.fabric.subscribe.status") private var status = true
    @AppStorage("settings.fabric.subscribe.roster") private var roster = true
    @AppStorage("settings.fabric.subscribe.proposals") private var proposals = true
    @AppStorage("settings.fabric.injectContext") private var injectContext = true

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $subscriptionMode) {
                    Text("Whole Channel").tag("Whole Channel")
                    Text("Mentions Only").tag("Mentions Only")
                    Text("Paused").tag("Paused")
                }
            }
            Section {
                Toggle("kind:9 chat messages", isOn: $chat)
                Toggle("kind:30315 live status", isOn: $status)
                Toggle("kind:30555 agent roster", isOn: $roster)
                Toggle("kind:30023 proposals", isOn: $proposals)
                Toggle("Inject unseen messages into coach context", isOn: $injectContext)
            } header: {
                Text("Event Kinds")
            } footer: {
                Text("The Rust subscription already asks for these kinds; Swift currently renders kind:9 traffic first.")
            }
        }
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FabricPublishingSettingsView: View {
    @AppStorage("settings.fabric.publish.sessionSummaries") private var sessionSummaries = true
    @AppStorage("settings.fabric.publish.planChanges") private var planChanges = true
    @AppStorage("settings.fabric.publish.externalReviews") private var externalReviews = false
    @AppStorage("settings.fabric.publish.failures") private var failures = true

    var body: some View {
        Form {
            Section {
                Toggle("Finished session summaries", isOn: $sessionSummaries)
                Toggle("Notable coach-applied changes", isOn: $planChanges)
                Toggle("External-change review notes", isOn: $externalReviews)
                Toggle("Errors and failures", isOn: $failures)
            } footer: {
                Text("This controls intent. Runtime posting gates can be tightened as each outbound event type is added.")
            }
        }
        .navigationTitle("Publishing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI

private struct AISettingsView: View {
    @Bindable var settings: AppSettings
    let coach: CoachController

    var body: some View {
        List {
            Section {
                SettingsNavigationRow(
                    title: "Providers",
                    subtitle: "Apple Intelligence, OpenRouter, Ollama",
                    value: settings.providerKind.label,
                    systemImage: "key",
                    destination: ProvidersSettingsView(settings: settings, coach: coach)
                )
                SettingsNavigationRow(
                    title: "Models",
                    subtitle: "Fast / Reasoning tier selection",
                    value: "\(CoachModelTier.allCases.count)",
                    systemImage: "cpu",
                    destination: ModelsSettingsView(settings: settings, coach: coach)
                )
                SettingsNavigationRow(
                    title: "Context & Privacy",
                    subtitle: "What enters hosted prompts",
                    value: "Redacted",
                    systemImage: "lock.shield",
                    destination: ContextPrivacySettingsView()
                )
                SettingsNavigationRow(
                    title: "Availability",
                    subtitle: "Disable AI, local-only, fallback behavior",
                    value: "Ready",
                    systemImage: "power",
                    destination: AIAvailabilitySettingsView()
                )
                SettingsNavigationRow(
                    title: "Usage / Cost",
                    subtitle: "Request counters and provider notes",
                    value: "Local",
                    systemImage: "chart.bar",
                    destination: AIUsageSettingsView()
                )
                SettingsNavigationRow(
                    title: "Voice",
                    subtitle: "Dictation provider and transcription key",
                    value: settings.transcriptionProviderKind.label,
                    systemImage: "mic",
                    destination: VoiceSettingsView(settings: settings)
                )
            }
        }
        .navigationTitle("AI")
    }
}

// MARK: - Voice

/// Transcription-provider choice + credentials (domain-primitives.md §10). Deliberately its own
/// section rather than folded into `ProvidersSettingsView` — the coach-provider keys above pick which
/// LLM answers a turn; this picks how the athlete's *voice* becomes text before that turn is ever
/// sent, an entirely independent axis (never touches `providerKind`/`CoachProviderKind`).
private struct VoiceSettingsView: View {
    @Bindable var settings: AppSettings

    @State private var elevenLabsKey = ""
    @State private var keyStatus: String?

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $settings.transcriptionProviderKind) {
                    ForEach(TranscriptionProviderKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.transcriptionProviderKind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Dictation")
            } footer: {
                Text("Used by the mic button in the coach chat, onboarding, and during workouts. The coach always receives plain text, regardless of which provider transcribed it.")
            }

            if settings.transcriptionProviderKind == .elevenLabs {
                Section {
                    SecureField("API key", text: $elevenLabsKey)
                        .textContentType(.password)
                        .onChange(of: elevenLabsKey) { _, newValue in saveKey(newValue) }
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(CoachSecrets.hasElevenLabsAPIKey() ? "Connected" : "Not connected")
                            .foregroundStyle(CoachSecrets.hasElevenLabsAPIKey() ? Color.green : Color.secondary)
                    }
                    if let keyStatus {
                        Text(keyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if CoachSecrets.hasElevenLabsAPIKey() {
                        Button("Disconnect ElevenLabs", role: .destructive) {
                            clearKey()
                        }
                    }
                } header: {
                    Text("ElevenLabs")
                } footer: {
                    Text("The API key is stored in Keychain, never in UserDefaults.")
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            elevenLabsKey = (try? CoachSecrets.elevenLabsAPIKey()) ?? ""
        }
    }

    private func saveKey(_ value: String) {
        try? CoachSecrets.setElevenLabsAPIKey(value)
        keyStatus = value.isEmpty ? nil : "Key saved to Keychain."
    }

    private func clearKey() {
        try? CoachSecrets.clearElevenLabsAPIKey()
        elevenLabsKey = ""
        keyStatus = "Key removed."
    }
}

private struct ProvidersSettingsView: View {
    @Bindable var settings: AppSettings
    let coach: CoachController

    @State private var openRouterKey = ""
    @State private var ollamaKey = ""
    @State private var keyStatus: String?
    @State private var byokConnector = BYOKProviderConnector()
    @State private var openRouterConnection: CoachProviderConnection?
    @State private var ollamaConnection: CoachProviderConnection?
    @State private var byokStatus: String?
    @State private var byokError: String?
    @State private var isConnectingBYOK = false
    @State private var ollamaModels: [String] = []
    @State private var isFetchingModels = false
    @State private var fetchModelsError: String?

    var body: some View {
        Form {
            Section {
                ProviderConnectionStatusRow(
                    provider: .openRouter,
                    connection: openRouterConnection,
                    hasStoredKey: CoachSecrets.hasAPIKey(for: .openRouter)
                )
                ProviderConnectionStatusRow(
                    provider: .ollama,
                    connection: ollamaConnection,
                    hasStoredKey: CoachSecrets.hasAPIKey(for: .ollama)
                )
                ProviderConnectionStatusRow(
                    provider: .appleIntelligence,
                    connection: nil,
                    hasStoredKey: false
                )

                Button {
                    Task { await connectWithBYOK(providers: CoachProviderKind.allCases.filter(\.supportsBYOK)) }
                } label: {
                    HStack {
                        Label("Connect Providers with BYOK", systemImage: "link.badge.plus")
                        Spacer()
                        if isConnectingBYOK { ProgressView() }
                    }
                }
                .disabled(isConnectingBYOK)

                if let byokStatus {
                    Text(byokStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let byokError {
                    Text(byokError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("BYOK")
            } footer: {
                Text("BYOK opens in the system browser with PKCE. Only selected provider keys are returned and stored in Keychain.")
            }

            Section {
                Picker("Provider", selection: $settings.providerKind) {
                    ForEach(CoachProviderKind.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.providerKind) { _, _ in coach.applySettings() }
            }

            switch settings.providerKind {
            case .openRouter:
                Section {
                    SecureField("API key", text: $openRouterKey)
                        .textContentType(.password)
                        .onChange(of: openRouterKey) { _, newValue in saveOpenRouterKey(newValue) }
                    if let keyStatus {
                        Text(keyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await connectWithBYOK(providers: [.openRouter]) }
                    } label: {
                        HStack {
                            Label(openRouterConnection == nil ? "Connect OpenRouter with BYOK" : "Reconnect OpenRouter with BYOK", systemImage: "link")
                            Spacer()
                            if isConnectingBYOK { ProgressView() }
                        }
                    }
                    .disabled(isConnectingBYOK)
                    Button("Test OpenRouter") {
                        keyStatus = openRouterKey.isEmpty ? "No key stored." : "Key is stored. Live test not run from Settings."
                    }
                    if CoachSecrets.hasAPIKey(for: .openRouter) {
                        Button("Disconnect OpenRouter", role: .destructive) {
                            clearProvider(.openRouter)
                        }
                    }
                } header: {
                    Text("OpenRouter")
                } footer: {
                    Text("The API key is stored in Keychain, never in UserDefaults.")
                }

            case .ollama:
                Section {
                    TextField("Base URL", text: $settings.ollamaBaseURL, prompt: Text("http://localhost:11434"))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { coach.applySettings() }

                    SecureField("API key (optional)", text: $ollamaKey)
                        .onChange(of: ollamaKey) { _, newValue in saveOllamaKey(newValue) }

                    Button {
                        Task { await connectWithBYOK(providers: [.ollama]) }
                    } label: {
                        HStack {
                            Label(ollamaConnection == nil ? "Connect Ollama with BYOK" : "Reconnect Ollama with BYOK", systemImage: "link")
                            Spacer()
                            if isConnectingBYOK { ProgressView() }
                        }
                    }
                    .disabled(isConnectingBYOK)

                    Button {
                        Task { await fetchOllamaModels() }
                    } label: {
                        HStack {
                            Text("Fetch Installed Models")
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
                    if CoachSecrets.hasAPIKey(for: .ollama) {
                        Button("Disconnect Ollama Key", role: .destructive) {
                            clearProvider(.ollama)
                        }
                    }
                    if !ollamaModels.isEmpty {
                        ForEach(ollamaModels, id: \.self) { name in
                            Text(name)
                        }
                    }
                } header: {
                    Text("Ollama")
                } footer: {
                    Text("A real iPhone cannot reach a Mac's localhost. Use a reachable LAN or remote URL for device use.")
                }

            case .appleIntelligence:
                let availability = AppleIntelligenceCoachProvider().availability
                Section {
                    LabeledContent("Status", value: availability.statusLabel)
                    Text(availability.message)
                        .foregroundStyle(.secondary)
                    Label("No API key or model selection required", systemImage: "lock.shield")
                        .font(.subheadline)
                } header: {
                    Text("Apple Intelligence")
                } footer: {
                    Text("Requests run through Apple's Foundation Models framework on this device. Workout context is not sent to OpenRouter or Ollama.")
                }
            }
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadStoredProviders()
        }
    }

    private func saveOpenRouterKey(_ value: String) {
        try? CoachSecrets.setOpenRouterAPIKey(value)
        keyStatus = value.isEmpty ? nil : "Key saved to Keychain."
        openRouterConnection = CoachSecrets.byokConnection(for: .openRouter)
        coach.applySettings()
    }

    private func saveOllamaKey(_ value: String) {
        try? CoachSecrets.setOllamaAPIKey(value)
        ollamaConnection = CoachSecrets.byokConnection(for: .ollama)
        coach.applySettings()
    }

    private func connectWithBYOK(providers: [CoachProviderKind]) async {
        isConnectingBYOK = true
        byokStatus = nil
        byokError = nil
        defer { isConnectingBYOK = false }

        do {
            let grants = try await byokConnector.connect(providers: providers)
            for grant in grants {
                _ = try CoachSecrets.saveBYOKGrant(grant)
            }
            reloadStoredProviders()
            coach.applySettings()
            byokStatus = "Connected \(grants.map { $0.provider.label }.joined(separator: ", "))."
        } catch {
            byokError = error.localizedDescription
        }
    }

    private func clearProvider(_ provider: CoachProviderKind) {
        do {
            try CoachSecrets.clearProvider(provider)
            switch provider {
            case .openRouter:
                openRouterKey = ""
                openRouterConnection = nil
            case .ollama:
                ollamaKey = ""
                ollamaConnection = nil
            case .appleIntelligence:
                break
            }
            keyStatus = nil
            byokStatus = "\(provider.label) key removed."
            byokError = nil
            coach.applySettings()
        } catch {
            byokError = error.localizedDescription
        }
    }

    private func reloadStoredProviders() {
        openRouterKey = (try? CoachSecrets.openRouterAPIKey()) ?? ""
        ollamaKey = (try? CoachSecrets.ollamaAPIKey()) ?? ""
        openRouterConnection = CoachSecrets.byokConnection(for: .openRouter)
        ollamaConnection = CoachSecrets.byokConnection(for: .ollama)
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
        } catch {
            fetchModelsError = "Could not reach Ollama at that URL."
        }
    }
}

private struct ProviderConnectionStatusRow: View {
    let provider: CoachProviderKind
    let connection: CoachProviderConnection?
    let hasStoredKey: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.label)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private var systemImage: String {
        switch provider {
        case .openRouter: return "sparkles"
        case .ollama: return "desktopcomputer"
        case .appleIntelligence: return "apple.intelligence"
        }
    }

    private var status: String {
        if provider == .appleIntelligence {
            return AppleIntelligenceCoachProvider().availability.statusLabel
        }
        if connection != nil { return "BYOK" }
        if hasStoredKey { return "Manual" }
        return "Not connected"
    }

    private var statusColor: Color {
        if provider == .appleIntelligence {
            return AppleIntelligenceCoachProvider().availability.isAvailable ? .green : .secondary
        }
        if connection != nil { return .green }
        if hasStoredKey { return .secondary }
        return .secondary
    }

    private var detail: String {
        if provider == .appleIntelligence {
            return AppleIntelligenceCoachProvider().availability.message
        }
        if let connection {
            return "\(connection.keyLabel) · \(connection.connectedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        if hasStoredKey { return "A key is stored in Keychain." }
        return "No provider key stored."
    }
}

private struct ModelsSettingsView: View {
    @Bindable var settings: AppSettings
    let coach: CoachController

    var body: some View {
        List {
            if settings.providerKind == .appleIntelligence {
                Section {
                    LabeledContent("Model", value: "On-device system model")
                    Text("Apple chooses and updates the model with iOS. Fast and Reasoning tiers don't apply to this provider.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text(AppleIntelligenceCoachProvider().availability.message)
                }
            } else {
                Section {
                    ForEach(CoachModelTier.allCases) { tier in
                        NavigationLink {
                            ModelTierSettingsView(settings: settings, coach: coach, tier: tier)
                        } label: {
                            HStack(spacing: 10) {
                                if settings.providerKind == .openRouter, !settings.model(for: tier).isEmpty {
                                    let providerID = settings.model(for: tier).split(separator: "/", maxSplits: 1).first.map(String.init) ?? "openrouter"
                                    ProviderLogoView(providerID: providerID, providerName: providerID, size: 26)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(tier.label)
                                        Spacer()
                                        Text(settings.model(for: tier).isEmpty ? "Unset" : settings.model(for: tier))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Text(tier.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } footer: {
                    Text("Fast is what the coach runs on by default. Reasoning falls back to Fast until you choose a distinct model — the coach switches to it itself for harder tasks.")
                }
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Both providers now go through the same fetched `ModelSelectorView` — OpenRouter fetches the public
/// catalog, Ollama fetches the local server's `/api/tags` (see `ModelCatalogSource`). Neither branch
/// ever shows a hardcoded suggestion list; the custom-id `TextField` is the only manual fallback,
/// and it's just placeholder text, never a default value.
private struct ModelTierSettingsView: View {
    @Bindable var settings: AppSettings
    let coach: CoachController
    let tier: CoachModelTier

    @State private var customModel = ""
    @State private var showingModelSelector = false

    private var source: ModelCatalogSource? {
        switch settings.providerKind {
        case .openRouter: return .openRouter
        case .ollama: return .ollama(baseURL: settings.ollamaBaseURL)
        case .appleIntelligence: return nil
        }
    }

    var body: some View {
        Form {
            Section {
                SettingsValueRow(title: "Provider", value: settings.providerKind.label)
                SettingsValueRow(title: "Current", value: settings.model(for: tier).isEmpty ? "Unset" : settings.model(for: tier))
            } footer: {
                Text(tier.detail)
            }

            Section {
                Button {
                    showingModelSelector = true
                } label: {
                    HStack(spacing: 12) {
                        ProviderLogoView(
                            providerID: currentProviderID,
                            providerName: currentProviderID
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.model(for: tier).isEmpty ? "Choose a model" : settings.model(for: tier))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(settings.providerKind == .openRouter ? "Browse OpenRouter models" : "Browse models installed on this Ollama server")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Model")
            } footer: {
                Text(
                    settings.providerKind == .openRouter
                        ? "Fetches the live OpenRouter catalog — search by name, provider, or price."
                        : "Fetches installed models from \(settings.ollamaBaseURL)."
                )
            }

            Section {
                TextField(settings.providerKind.modelPlaceholder, text: $customModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Use Custom Model ID") {
                    let trimmed = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    settings.setModel(trimmed, for: tier)
                    if tier == .fast {
                        coach.applySettings(tier: .fast)
                    }
                    customModel = ""
                }
                .disabled(customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Custom")
            }
        }
        .navigationTitle(tier.label)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            customModel = settings.model(for: tier)
        }
        .sheet(isPresented: $showingModelSelector) {
            if let source {
                NavigationStack {
                    ModelSelectorView(
                        source: source,
                        selectedModelID: Binding(
                            get: { settings.model(for: tier) },
                            set: { newValue in
                                settings.setModel(newValue, for: tier)
                                if tier == .fast {
                                    coach.applySettings(tier: .fast)
                                }
                            }
                        )
                    )
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    /// Best-effort maker id parsed straight from the current model id ("anthropic/claude-…" →
    /// "anthropic") for the row's logo — the full catalog lookup only happens once the sheet opens.
    private var currentProviderID: String {
        let current = settings.model(for: tier)
        if settings.providerKind == .appleIntelligence { return "apple" }
        return current.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "openrouter"
    }
}

private struct ContextPrivacySettingsView: View {
    @AppStorage("settings.ai.context.currentWorkout") private var currentWorkout = true
    @AppStorage("settings.ai.context.recentHistory") private var recentHistory = true
    @AppStorage("settings.ai.context.transcriptMemory") private var transcriptMemory = true
    @AppStorage("settings.ai.context.doctrine") private var doctrine = true
    @AppStorage("settings.ai.context.externalReviews") private var externalReviews = true
    @AppStorage("settings.ai.context.fabric") private var fabric = true
    @AppStorage("settings.ai.context.redactHosted") private var redactHosted = true

    var body: some View {
        Form {
            Section("Included Context") {
                Toggle("Current workout state", isOn: $currentWorkout)
                Toggle("Recent workout history", isOn: $recentHistory)
                Toggle("Coach transcript memory", isOn: $transcriptMemory)
                Toggle("Training doctrine", isOn: $doctrine)
                Toggle("External sync reviews", isOn: $externalReviews)
                Toggle("Recent tenex-edge traffic", isOn: $fabric)
            }
            Section {
                Toggle("Redact sensitive notes for hosted providers", isOn: $redactHosted)
            } footer: {
                Text("Current runtime uses the existing context assembly. These controls make the intended privacy envelope explicit.")
            }
        }
        .navigationTitle("Context")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AIAvailabilitySettingsView: View {
    @AppStorage("settings.ai.enabled") private var enabled = true
    @AppStorage("settings.ai.preferLocal") private var preferLocal = false
    @AppStorage("settings.ai.cellularHosted") private var cellularHosted = true
    @AppStorage("settings.ai.offlineUsable") private var offlineUsable = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI features", isOn: $enabled)
                Toggle("Prefer local providers when reachable", isOn: $preferLocal)
                Toggle("Allow hosted providers on cellular", isOn: $cellularHosted)
                Toggle("Keep app usable when AI is offline", isOn: $offlineUsable)
            }
        }
        .navigationTitle("Availability")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AIUsageSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "Live coach turns", value: "Stored locally")
                SettingsValueRow(title: "Plan generations", value: "Best effort")
                SettingsValueRow(title: "External reviews", value: "Best effort")
            } footer: {
                Text("Provider billing metadata is not collected by Workout.md today.")
            }
        }
        .navigationTitle("Usage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Workout

/// Deliberately has no "Athlete" section. Goals, schedule, equipment, injuries/constraints, and
/// exercise preferences are facts the COACH learns and keeps as durable memory — populated by the
/// onboarding conversation and ongoing chat via `memory_add` — never settings the user fills in
/// here. See `CoachMemorySettingsView` (Coach → Coach Memory) for the transparent, editable view
/// of that memory. This screen only covers app-behavior preferences for what happens during a
/// workout.
private struct WorkoutSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        List {
            Section {
                SettingsNavigationRow(
                    title: "Capture Defaults",
                    subtitle: "RPE/RIR, rest timer, haptics, units",
                    value: "RPE",
                    systemImage: "checklist",
                    destination: CaptureDefaultsSettingsView()
                )
                SettingsNavigationRow(
                    title: "Deviation Handling",
                    subtitle: "Pain, fatigue, time, equipment prompts",
                    value: "Quiet",
                    systemImage: "arrow.triangle.branch",
                    destination: DeviationHandlingSettingsView()
                )
                SettingsNavigationRow(
                    title: "Plan Repair",
                    subtitle: "Missed-session behavior",
                    value: "Ask",
                    systemImage: "wrench.adjustable",
                    destination: PlanRepairSettingsView()
                )
            } header: {
                Text("During Workout")
            }
        }
        .navigationTitle("Workout")
    }
}

private struct CaptureDefaultsSettingsView: View {
    @AppStorage("settings.capture.effortScale") private var effortScale = "RPE"
    @AppStorage("settings.capture.startRestTimer") private var startRestTimer = true
    @AppStorage("settings.capture.haptics") private var haptics = true
    @AppStorage("settings.capture.timedCountdown") private var timedCountdown = true
    @AppStorage("settings.capture.prefillFromPlan") private var prefillFromPlan = true
    /// Weight-display units are an app-behavior preference (how numbers are shown), not an
    /// athlete fact, so this lives here rather than in coach memory — unlike the deleted Equipment
    /// screen's gym/plates fields, which were athlete facts the coach should learn instead.
    @AppStorage("settings.workout.units") private var units = "lb"

    var body: some View {
        Form {
            Section {
                Picker("Units", selection: $units) {
                    Text("lb").tag("lb")
                    Text("kg").tag("kg")
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Effort scale", selection: $effortScale) {
                    Text("RPE").tag("RPE")
                    Text("RIR").tag("RIR")
                    Text("None").tag("None")
                }
                .pickerStyle(.segmented)
                Toggle("Start rest timer after logging", isOn: $startRestTimer)
                Toggle("Haptics", isOn: $haptics)
                Toggle("Timed-set countdown", isOn: $timedCountdown)
                Toggle("Prefill from plan", isOn: $prefillFromPlan)
            }
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeviationHandlingSettingsView: View {
    @AppStorage("settings.deviation.painPrompt") private var painPrompt = true
    @AppStorage("settings.deviation.missedRepsPrompt") private var missedRepsPrompt = true
    @AppStorage("settings.deviation.equipmentPrompt") private var equipmentPrompt = true
    @AppStorage("settings.deviation.quietDuringSet") private var quietDuringSet = true

    var body: some View {
        Form {
            Section {
                Toggle("Ask after pain flag", isOn: $painPrompt)
                Toggle("Ask after missed reps twice", isOn: $missedRepsPrompt)
                Toggle("Offer substitution when equipment unavailable", isOn: $equipmentPrompt)
                Toggle("Keep prompts quiet during active set", isOn: $quietDuringSet)
            }
        }
        .navigationTitle("Deviations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlanRepairSettingsView: View {
    @AppStorage("settings.repair.strategy") private var strategy = "Ask"
    @AppStorage("settings.repair.absenceThreshold") private var absenceThreshold = 7
    @AppStorage("settings.repair.noCatchup") private var noCatchup = true
    @AppStorage("settings.repair.preferDeload") private var preferDeload = true
    @AppStorage("settings.repair.showSummary") private var showSummary = true

    var body: some View {
        Form {
            Section {
                Picker("After missed sessions", selection: $strategy) {
                    Text("Skip Forward").tag("Skip Forward")
                    Text("Resume").tag("Resume")
                    Text("Ask").tag("Ask")
                }
                Stepper(value: $absenceThreshold, in: 1...30) {
                    LabeledContent("Absence threshold", value: "\(absenceThreshold) days")
                }
                Toggle("Do not create catch-up workouts", isOn: $noCatchup)
                Toggle("Prefer deload after long absence", isOn: $preferDeload)
                Toggle("Show repair summary before applying", isOn: $showSummary)
            }
        }
        .navigationTitle("Plan Repair")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data

private struct DataSettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var modelContext

    @State private var isRestoring = false
    @State private var restoreResult: String?

    var body: some View {
        List {
            Section {
                SettingsNavigationRow(
                    title: "Integrations",
                    subtitle: "GitHub, iCloud, local files",
                    value: "2",
                    systemImage: "plus.rectangle.on.folder",
                    destination: IntegrationsSettingsView()
                )
                SettingsNavigationRow(
                    title: "GitHub",
                    subtitle: "Repo, token, pending commits",
                    value: SyncManager.shared.isAuthenticated ? "Signed in" : "No token",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    destination: GitHubSettingsView(settings: settings)
                )
                SettingsNavigationRow(
                    title: "iCloud",
                    subtitle: "Markdown mirror in iCloud Drive",
                    value: settings.icloudSyncEnabled ? "On" : "Off",
                    systemImage: "icloud",
                    destination: ICloudSettingsView(settings: settings)
                )
            } header: {
                Text("Destinations")
            }

            Section {
                SettingsNavigationRow(
                    title: "Markdown",
                    subtitle: "Export shape and paths",
                    value: "Sessions",
                    systemImage: "doc.plaintext",
                    destination: MarkdownSettingsView()
                )
                SettingsNavigationRow(
                    title: "Import",
                    subtitle: "Import sessions, plans, doctrine",
                    value: "Preview",
                    systemImage: "square.and.arrow.down",
                    destination: ImportSettingsView()
                )
                SettingsNavigationRow(
                    title: "Conflict Policy",
                    subtitle: "External edits and sync cadence",
                    value: "Review",
                    systemImage: "exclamationmark.triangle",
                    destination: ConflictPolicySettingsView()
                )
                SettingsNavigationRow(
                    title: "Backups",
                    subtitle: "Create and restore backups",
                    value: "Manual",
                    systemImage: "archivebox",
                    destination: BackupsSettingsView()
                )
                SettingsNavigationRow(
                    title: "Data Control",
                    subtitle: "Clear memory, wipe keys, reset",
                    value: "Destructive",
                    systemImage: "trash",
                    destination: DataControlSettingsView()
                )
            } header: {
                Text("Ownership")
            }

            Section {
                Button {
                    Task { await runRestore() }
                } label: {
                    HStack {
                        Label("Restore from Sync", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .disabled(isRestoring)

                if let restoreResult {
                    Text(restoreResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Fetches every plan and session Markdown file from GitHub/iCloud and reconstructs "
                     + "plans and history on this device — the fresh-install / second-device path "
                     + "(domain-primitives.md §11). Safe to run more than once: plans land as a new "
                     + "revision if changed, and completed sessions are never overwritten.")
            }
        }
        .navigationTitle("Data")
    }

    private func runRestore() async {
        isRestoring = true
        defer { isRestoring = false }
        let summary = await SyncManager.shared.restoreFromSync(context: modelContext)
        restoreResult = "Restored \(summary.plansImported) plan(s), \(summary.sessionsImported) session(s) — "
            + "skipped \(summary.skippedNoCanonicalBlock) file(s) with no canonical data."
    }
}

private struct IntegrationsSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "GitHub", value: "Private Markdown repo")
                SettingsValueRow(title: "iCloud", value: "Documents mirror")
                SettingsValueRow(title: "Local folder", value: "Not configured")
            }
            Section {
                Button {
                    // Future integration picker.
                } label: {
                    Label("Add Integration", systemImage: "plus")
                }
                .disabled(true)
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GitHubSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var manager = SyncManager.shared
    @State private var auth = GitHubAuth.shared
    @State private var token = ""
    @State private var isAuthenticating = false
    @State private var deviceCode: GitHubAuth.DeviceCodeResponse?
    @State private var deviceFlowError: String?
    @State private var showAdvancedPAT = false

    private var deviceFlowConfigured: Bool {
        let id = GitHubAuth.deviceFlowClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !id.isEmpty && !id.hasPrefix("TODO_")
    }

    var body: some View {
        Form {
            Section {
                gitHubAuthContent

                DisclosureGroup("Advanced: personal access token", isExpanded: $showAdvancedPAT) {
                    SecureField("Personal access token", text: $token)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: token) { _, newValue in
                            if newValue.isEmpty {
                                try? auth.clearToken()
                            } else {
                                try? auth.setToken(newValue)
                                Task { try? await auth.fetchCurrentUser() }
                            }
                        }

                    Text("Fallback for when device sign-in is unavailable: paste a fine-grained or classic PAT with repo scope.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(deviceFlowConfigured
                    ? "GitHub sign-in uses OAuth device flow. Tokens are stored only in the Keychain."
                    : "GitHub device sign-in needs a registered OAuth App client id; use a personal access token meanwhile.")
            }

            Section {
                TextField("Repo name", text: $settings.githubRepoName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: settings.githubRepoName) { _, newValue in
                        manager.sync.setRepoName(newValue)
                    }
            } footer: {
                Text("The repo stores generated Markdown and sync state for this workout log.")
            }

            Section {
                SettingsValueRow(title: "Status", value: manager.status.label)
                SettingsValueRow(title: "Signed in", value: manager.isAuthenticated ? (auth.login.map { "@\($0)" } ?? "Yes") : "No token")
                if let lastSyncedAt = manager.lastSyncedAt {
                    SettingsValueRow(title: "Last synced", value: lastSyncedAt.formatted(date: .abbreviated, time: .shortened))
                }
                SettingsValueRow(title: "Pending commits", value: "\(manager.pendingCommitCount)")
            }

            Section {
                Button {
                    Task { await manager.pullNow() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!manager.isAuthenticated)
            }
        }
        .navigationTitle("GitHub")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            token = (try? auth.currentToken()) ?? ""
            if auth.isAuthenticated {
                Task { try? await auth.fetchCurrentUser() }
            }
        }
    }

    @ViewBuilder
    private var gitHubAuthContent: some View {
        if auth.isAuthenticated {
            SettingsValueRow(title: "Signed in as", value: auth.login.map { "@\($0)" } ?? "GitHub")
            Button(role: .destructive) {
                signOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } else if let deviceCode {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter this code at \(deviceCode.verificationUri):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(deviceCode.userCode)
                        .font(.title2.monospaced().bold())
                    Spacer()
                    Button {
                        UIPasteboard.general.string = deviceCode.userCode
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy code")
                }
                if let url = URL(string: deviceCode.verificationUri) {
                    Link(destination: url) {
                        Label("Open GitHub", systemImage: "arrow.up.forward.app")
                    }
                }
                if isAuthenticating {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Waiting for approval...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Cancel") {
                    isAuthenticating = false
                    self.deviceCode = nil
                }
                .font(.caption)
            }
        } else if deviceFlowConfigured {
            Button {
                startDeviceFlow()
            } label: {
                if isAuthenticating {
                    HStack {
                        ProgressView()
                        Text("Starting...")
                    }
                } else {
                    Label("Sign in with GitHub", systemImage: "person.badge.key")
                }
            }
            .disabled(isAuthenticating)
        } else {
            Label("GitHub sign-in not configured yet", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }

        if let deviceFlowError {
            Text(deviceFlowError)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func startDeviceFlow() {
        isAuthenticating = true
        deviceFlowError = nil
        deviceCode = nil
        Task {
            do {
                try await auth.authenticateWithDeviceFlow { response in
                    Task { @MainActor in deviceCode = response }
                }
                await MainActor.run {
                    isAuthenticating = false
                    deviceCode = nil
                }
                _ = try? await auth.fetchCurrentUser()
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    deviceCode = nil
                    deviceFlowError = String(describing: error)
                }
            }
        }
    }

    private func signOut() {
        try? auth.clearToken()
        token = ""
        deviceFlowError = nil
    }
}

private struct ICloudSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var manager = SyncManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("iCloud sync", isOn: $settings.icloudSyncEnabled)
                    .onChange(of: settings.icloudSyncEnabled) { _, enabled in
                        manager.icloudToggleChanged(enabled: enabled)
                    }
                SettingsValueRow(title: "Status", value: manager.icloudStatus.label)
                SettingsValueRow(title: "Available", value: manager.isICloudAvailable ? "Yes" : "No")
                if settings.icloudSyncEnabled && !manager.isICloudAvailable {
                    Text("Not signed in to iCloud, or iCloud Drive is off for this app.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let lastICloudSyncedAt = manager.lastICloudSyncedAt {
                    SettingsValueRow(title: "Last synced", value: lastICloudSyncedAt.formatted(date: .abbreviated, time: .shortened))
                }
            } footer: {
                Text("iCloud mirrors the same Markdown into this app's iCloud Drive container. It is independent of GitHub.")
            }

            Section {
                Button {
                    Task { await manager.pullICloudNow() }
                } label: {
                    Label("Sync iCloud Now", systemImage: "icloud.and.arrow.up")
                }
                .disabled(!settings.icloudSyncEnabled)
            }
        }
        .navigationTitle("iCloud")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MarkdownSettingsView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @AppStorage("settings.markdown.includePlans") private var includePlans = true
    @AppStorage("settings.markdown.includeCoachNotes") private var includeCoachNotes = true
    @AppStorage("settings.markdown.includeRPE") private var includeRPE = true
    @AppStorage("settings.markdown.includeDoctrineReferences") private var includeDoctrineReferences = false

    private var combinedMarkdown: String {
        guard !records.isEmpty else { return "# Workout.md\n\nNo sessions logged yet.\n" }
        return records.map(MarkdownGenerator.renderSession).joined(separator: "\n---\n\n")
    }

    var body: some View {
        Form {
            Section("Include") {
                Toggle("Plans", isOn: $includePlans)
                Toggle("Coach notes", isOn: $includeCoachNotes)
                Toggle("RPE and deviations", isOn: $includeRPE)
                Toggle("Doctrine references", isOn: $includeDoctrineReferences)
            }
            Section {
                ShareLink(
                    item: MarkdownFile(text: combinedMarkdown, filename: "workout-history.md"),
                    preview: SharePreview("workout-history.md")
                ) {
                    Label("Export All Sessions", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Current export always uses the canonical session renderer; include toggles define the next export-policy pass.")
            }
        }
        .navigationTitle("Markdown")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ImportSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "Markdown sessions", value: "Preview first")
                SettingsValueRow(title: "Plan files", value: "Map blocks")
                SettingsValueRow(title: "Doctrine", value: "Import as docs")
            }
            Section {
                Button {
                    // Future document picker.
                } label: {
                    Label("Choose Files", systemImage: "doc.badge.plus")
                }
                .disabled(true)
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ConflictPolicySettingsView: View {
    @AppStorage("settings.sync.conflictPolicy") private var conflictPolicy = "Review"
    @AppStorage("settings.sync.pullCadence") private var pullCadence = "15 minutes"
    @AppStorage("settings.sync.reviewExternalEdits") private var reviewExternalEdits = true
    @AppStorage("settings.sync.allowCellular") private var allowCellular = true

    var body: some View {
        Form {
            Section {
                Picker("External edits", selection: $conflictPolicy) {
                    Text("Review").tag("Review")
                    Text("Apply").tag("Apply")
                    Text("Ignore").tag("Ignore")
                }
                TextField("Pull cadence", text: $pullCadence)
                Toggle("Review external edits with coach", isOn: $reviewExternalEdits)
                Toggle("Allow sync on cellular", isOn: $allowCellular)
            }
        }
        .navigationTitle("Conflicts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BackupsSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "Last backup", value: "Never")
                SettingsValueRow(title: "Includes", value: "History, plans, settings, doctrine")
                SettingsValueRow(title: "Secrets", value: "Excluded")
            }
            Section {
                Button("Create Backup") {}
                    .disabled(true)
                Button("Restore Backup") {}
                    .disabled(true)
            }
        }
        .navigationTitle("Backups")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DataControlSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    @State private var confirmResetOnboarding = false
    @State private var confirmClearMemory = false

    var body: some View {
        List {
            Section {
                Button(role: .destructive) { confirmClearMemory = true } label: {
                    Label("Clear Coach Memory", systemImage: "trash")
                }
                Button(role: .destructive) {} label: {
                    Label("Delete Local Workout History", systemImage: "trash")
                }
                .disabled(true)
                Button(role: .destructive) {} label: {
                    Label("Wipe All Credentials", systemImage: "key.slash")
                }
                .disabled(true)
                Button("Reset Onboarding") { confirmResetOnboarding = true }
            } footer: {
                Text("Reset Onboarding returns you to the setup flow and clears the coach's memory and active plan so you can start fresh. Your completed workout history is kept.")
            }
        }
        .navigationTitle("Data Control")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset onboarding?", isPresented: $confirmResetOnboarding, titleVisibility: .visible) {
            Button("Reset Onboarding", role: .destructive) { resetOnboarding() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shows the setup flow again and clears the coach's memory and deactivates your active plan so it builds fresh. Completed workout history is kept.")
        }
        .confirmationDialog("Clear coach memory?", isPresented: $confirmClearMemory, titleVisibility: .visible) {
            Button("Clear Memory", role: .destructive) { clearCoachMemory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deletes everything the coach has remembered about you. This can't be undone.")
        }
    }

    /// Returns the app to a first-run onboarding state: clears durable coach memory, deactivates
    /// every plan (so onboarding's "you're set" doesn't instantly appear and the coach builds a new
    /// plan from a fresh conversation), discards any in-progress session, then flips `hasOnboarded`
    /// off so `RootView` shows `OnboardingView` again. Completed `WorkoutRecord` history is preserved.
    private func resetOnboarding() {
        clearCoachMemory()
        if let plans = try? modelContext.fetch(FetchDescriptor<PlanRecord>()) {
            for plan in plans { plan.isActive = false }
        }
        ActiveSessionStore(context: modelContext).discard()
        try? modelContext.save()
        settings.hasOnboarded = false
    }

    private func clearCoachMemory() {
        guard let memories = try? modelContext.fetch(FetchDescriptor<MemoryRecord>()) else { return }
        for memory in memories { modelContext.delete(memory) }
        try? modelContext.save()
    }
}

// MARK: - Advanced

private struct AdvancedSettingsView: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController

    var body: some View {
        List {
            Section {
                SettingsNavigationRow(
                    title: "Diagnostics",
                    subtitle: "Test providers, sync, fabric relay",
                    value: "Ready",
                    systemImage: "stethoscope",
                    destination: DiagnosticsSettingsView(settings: settings, fabric: fabric)
                )
                SettingsNavigationRow(
                    title: "Prompt Preview",
                    subtitle: "Redacted assembled coach context",
                    value: "Redacted",
                    systemImage: "eye",
                    destination: PromptPreviewSettingsView(settings: settings, fabric: fabric)
                )
                SettingsNavigationRow(
                    title: "Fabric Debug",
                    subtitle: "Raw relay and subscription state",
                    value: fabric.status.compactLabel,
                    systemImage: "ladybug",
                    destination: FabricDebugSettingsView(settings: settings, fabric: fabric)
                )
                SettingsNavigationRow(
                    title: "Storage",
                    subtitle: "SwiftData, queues, doctrine files",
                    value: "Local",
                    systemImage: "internaldrive",
                    destination: StorageSettingsView()
                )
                #if DEBUG
                SettingsNavigationRow(
                    title: "Developer",
                    subtitle: "Debug-only actions",
                    value: "Debug",
                    systemImage: "hammer",
                    destination: DeveloperSettingsView()
                )
                #endif
                SettingsNavigationRow(
                    title: "About",
                    subtitle: "Version, privacy summary, licenses",
                    value: "1.0",
                    systemImage: "info.circle",
                    destination: AboutSettingsView()
                )
            }
        }
        .navigationTitle("Advanced")
    }
}

private struct DiagnosticsSettingsView: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController
    @State private var result = "Ready."

    var body: some View {
        List {
            Section {
                Button("Test AI Provider") { result = "Provider: \(settings.providerKind.label). Key and network test not run." }
                Button("Test GitHub") { result = "GitHub: \(SyncManager.shared.isAuthenticated ? "token stored" : "no token")." }
                Button("Test iCloud") { result = "iCloud: \(SyncManager.shared.icloudStatus.label)." }
                Button("Test Fabric Relay") { result = "Fabric: \(fabric.status.label)." }
            }
            Section("Result") {
                Text(result)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PromptPreviewSettingsView: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section {
                Text(redactedPromptPreview)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            } footer: {
                Text("Secrets are redacted. This is a settings preview, not a live prompt capture from a current workout.")
            }
        }
        .navigationTitle("Prompt Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var redactedPromptPreview: String {
        let memoryDigest = MemoryStore(context: modelContext).digest()
        return """
        System:
        \(String(settings.effectiveSystemPrompt.prefix(700)))

        Memory:
        \(memoryDigest.isEmpty ? "(empty)" : memoryDigest)

        Doctrine:
        \(settings.doctrineEnabled ? "Enabled" : "Disabled")

        Fabric:
        \(fabric.messages.isEmpty ? "(no buffered messages)" : "[recent messages redacted]")

        Secrets:
        [redacted]
        """
    }
}

private struct FabricDebugSettingsView: View {
    @Bindable var settings: AppSettings
    let fabric: FabricController

    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "Status", value: fabric.status.label)
                SettingsValueRow(title: "Channel", value: settings.fabricChannel.isEmpty ? "Unset" : settings.fabricChannel)
                SettingsValueRow(title: "Relays", value: settings.fabricRelaysList.joined(separator: ", "))
                SettingsValueRow(title: "Indexer", value: settings.fabricIndexerRelay)
                SettingsValueRow(title: "Buffered messages", value: "\(fabric.messages.count)")
                SettingsValueRow(title: "Last publish error", value: fabric.lastPublishError ?? "None")
            }
        }
        .navigationTitle("Fabric Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StorageSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "SwiftData", value: "Local store, CloudKit disabled")
                SettingsValueRow(title: "Doctrine", value: "Application Support JSON")
                SettingsValueRow(title: "GitHub queue", value: "\(SyncManager.shared.pendingCommitCount) pending")
                SettingsValueRow(title: "iCloud hash index", value: "UserDefaults")
                SettingsValueRow(title: "Provider keys", value: "Keychain")
                SettingsValueRow(title: "Fabric nsec", value: "Keychain")
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
private struct DeveloperSettingsView: View {
    var body: some View {
        List {
            Section {
                Button("Debug actions live under Doctrine and tenex-edge where they have context.") {}
                    .disabled(true)
            }
        }
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

private struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsValueRow(title: "App", value: "Workout.md")
                SettingsValueRow(title: "Version", value: "1.0")
                SettingsValueRow(title: "Data posture", value: "Local-first Markdown")
                SettingsValueRow(title: "Secrets", value: "Keychain")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Doctrine add sheet

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
            .navigationTitle("Add Doctrine")
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
