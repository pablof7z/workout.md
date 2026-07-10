import SwiftUI
import SwiftData

/// The live LLM coach, scoped to the current exercise. Full-bleed dark (same aesthetic as the
/// runner — NOT a sheet, NOT web cards). The user types a plain-language note; `CoachController`
/// streams a real model reply (rig.rs, over UniFFI) token by token into the transcript, and any
/// tool call the model makes applies a concrete change to the shared `WorkoutSession` — shown as a
/// distinct applied-diff line — which reflects on the runner's upcoming pages. The coach voice is
/// dry and direct — no pep talk (enforced by the system prompt, not by scripting here anymore).
struct CoachView: View {
    @Environment(WorkoutSession.self) private var session
    @Environment(CoachController.self) private var coach
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    var onBackToRunner: () -> Void

    @State private var draft = ""
    @State private var showingSettings = false
    @FocusState private var inputFocused: Bool

    private var exerciseName: String { session.currentExerciseName ?? "This exercise" }
    private var moodKey: MoodKey { session.currentStep?.moodKey ?? .rest }
    private var messages: [CoachMessage] { session.transcript(for: exerciseName) }

    /// True once the currently-selected provider has a credential to actually talk to — `openRouter`
    /// needs a stored API key; `ollama` is a deliberate user choice (its base URL may be a reachable
    /// remote host), so it's never treated as "unconfigured" here. Keeps first-run calm: rather than
    /// sending a turn that's certain to fail and showing a raw connection error, `CoachView` shows a
    /// quiet inline nudge toward Settings instead (see `unconfiguredState`).
    private var isCoachConfigured: Bool {
        switch settings.providerKind {
        case .openRouter:
            let key = (try? CoachSecrets.openRouterAPIKey()) ?? nil
            return !(key ?? "").isEmpty
        case .ollama:
            return true
        }
    }

    var body: some View {
        ZStack {
            BackgroundView(moodKey: moodKey)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if isCoachConfigured {
                    transcript
                    deloadChip
                    inputBar
                } else {
                    Spacer()
                    unconfiguredState
                    Spacer()
                }
            }
        }
        .onAppear { session.seedTranscriptIfNeeded(for: exerciseName) }
        .onChange(of: exerciseName) { _, newValue in
            session.seedTranscriptIfNeeded(for: newValue)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("COACH")
                    .font(.caption.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))
                Text(exerciseName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Coach settings")

                    Button(action: onBackToRunner) {
                        HStack(spacing: 4) {
                            Text("Set")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Back to the set")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 12)
    }

    // MARK: Unconfigured (no provider key yet)

    /// A calm, on-brand placeholder shown instead of the transcript/input when there's no coach
    /// credential to actually send a turn with — replaces what used to be a raw connection-error
    /// transcript on first run (the default provider, and its base URL, live in `AppSettings`).
    private var unconfiguredState: some View {
        VStack(spacing: 14) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
            Text("Your coach isn't set up yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Add a provider key to get live, personalized guidance during your sets.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.impact(.light)
                showingSettings = true
            } label: {
                Text("Set up your coach in Settings")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .frame(height: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.indigo)
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
        .accessibilityElement(children: .combine)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        CoachLineView(message: message)
                            .id(message.id)
                    }
                    if isWaitingForFirstToken {
                        ThinkingIndicator()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut) { scroll.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: messages.last?.text) { _, _ in
                if let last = messages.last {
                    scroll.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// True right after a turn is sent, before the first `on_text_delta` chunk has arrived — the
    /// streaming placeholder message exists but is still empty.
    private var isWaitingForFirstToken: Bool {
        coach.isSending && messages.last?.kind == .coach && (messages.last?.text.isEmpty ?? false)
    }

    // MARK: Deload follow-up chip

    @ViewBuilder
    private var deloadChip: some View {
        if session.offerDeload.contains(exerciseName) {
            HStack {
                Button {
                    Haptics.impact(.light)
                    session.applyDeload()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.minus")
                        Text("Deload 2 weeks")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.indigo).interactive(), in: .capsule)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }

    // MARK: Input

    private var inputBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                TextField("How did it feel?", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .tint(.indigo)
                    .lineLimit(1...3)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .glassEffect(.regular, in: .capsule)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.glassProminent)
                .tint(.indigo)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || coach.isSending)
                .accessibilityLabel("Send to coach")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !coach.isSending else { return }
        Haptics.selection()
        draft = ""
        inputFocused = false
        let scopedExercise = exerciseName
        withAnimation(.snappy) {
            coach.send(userMessage: text, exerciseName: scopedExercise, session: session, modelContext: modelContext)
        }
    }
}

/// A terse "thinking" line shown between the turn being sent and the first streamed token —
/// intentionally understated, matching the rest of the transcript's plain-line style.
private struct ThinkingIndicator: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.bubble")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.6))
            Spacer(minLength: 24)
        }
        .accessibilityLabel("Coach is thinking")
    }
}

/// One transcript line. Coach lines carry a quote glyph; user lines are trailing-aligned and
/// secondary; applied-diff lines get a distinct branch glyph and an indigo/green accent — none of
/// these are big chat bubbles or cards, just terse lines.
private struct CoachLineView: View {
    let message: CoachMessage

    var body: some View {
        switch message.kind {
        case .coach:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.bubble")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 24)
            }

        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .diff:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.footnote.weight(.bold))
                Text(message.text)
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 24)
            }
            .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.55))
            .padding(.leading, 4)
        }
    }
}
