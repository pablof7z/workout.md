import SwiftUI
import SwiftData

/// A full-bleed coach conversation surface — transcript + glass input bar — reused by every UI
/// surface whose job is to get the coach to CREATE or UPDATE the active plan via `plan_apply`
/// rather than a bespoke one-shot pipeline (`docs/architecture/domain-primitives.md` §9,
/// invariants 1/2: the coach creates plans ONLY through the general `plan_apply` path). Extracted
/// from what used to be `OnboardingView`'s body (slice 8) so onboarding and the "Generate from
/// Goal" sheet (`GeneratePlanSheet`) share exactly one conversation implementation instead of
/// onboarding's real coach turn and a second, separate structured-JSON generation call.
///
/// `onActivePlan` fires when the caller's own "ready" affordance (shown once an active plan
/// exists) is tapped — deliberately a manual tap rather than auto-firing the instant `plan_apply`
/// lands, so the athlete can read the coach's reply (and keep refining the plan conversationally)
/// before the surface goes away.
struct CoachConversationView: View {
    let mode: CoachMode
    var eyebrow: String = "COACH"
    let headline: String
    var placeholder: String = "Tell me about your training…"
    var readyLabel: String = "You're set — Enter"
    var skipLabel: String = "Continue without a plan"
    var proposalOnly: Bool = false
    var onActivePlan: () -> Void
    /// `nil` hides the skip affordance entirely — not every surface this view is embedded in has a
    /// meaningful "skip" outcome (e.g. a sheet whose only exit is Cancel in the toolbar).
    var onSkip: (() -> Void)?

    @Environment(CoachController.self) private var coach
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<PlanRecord> { $0.isActive == true }) private var activePlans: [PlanRecord]

    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var streamingMessageID: UUID?
    /// Flipped by `ConnectCoachView.onConnected` the instant the athlete saves a credential (or picks
    /// Ollama), so the transcript appears on the very next render — `isCoachConfigured` alone can't
    /// drive this because it reads the Keychain, which SwiftUI's observation tracking has no visibility
    /// into (a plain re-check on the next unrelated body evaluation could take a while to happen).
    @State private var coachJustConnected = false
    /// Guards the onboarding auto-bootstrap turn (see `startOnboardingBootstrap`) so it fires exactly
    /// once even though both `.onAppear` and the `showConversation` `.onChange` call `seedIfNeeded`.
    @State private var hasStartedOnboardingBootstrap = false
    @State private var planProposal: PlanSnapshot?
    @State private var acceptanceError: String?
    @FocusState private var inputFocused: Bool

    private var isReady: Bool {
        proposalOnly ? planProposal != nil : OnboardingCompletion.isComplete(activePlans: activePlans)
    }

    /// Mirrors `CoachView.isCoachConfigured` — `openRouter` needs a stored key; `ollama` is a
    /// deliberate user choice, never treated as unconfigured.
    private var isCoachConfigured: Bool {
        switch settings.providerKind {
        case .openRouter:
            let key = (try? CoachSecrets.openRouterAPIKey()) ?? nil
            return !(key ?? "").isEmpty
        case .ollama:
            return true
        case .appleIntelligence:
            return AppleIntelligenceCoachProvider().availability.isAvailable
        }
    }

    /// What the view actually keys its transcript/footer on — `isCoachConfigured` OR the just-connected
    /// flag `ConnectCoachView` sets, so connecting doesn't require an unrelated re-render to notice.
    private var showConversation: Bool { isCoachConfigured || coachJustConnected }

    var body: some View {
        VStack(spacing: 0) {
            header
            if showConversation {
                transcript
                footer
            } else {
                ConnectCoachView(onConnected: { coachJustConnected = true })
                footer
            }
        }
        .onAppear(perform: seedIfNeeded)
        .onChange(of: showConversation) { _, isConfigured in
            if isConfigured { seedIfNeeded() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.55))
            Text(headline)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .padding(.bottom, 12)
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
                    if let proposal = planProposal {
                        PlanProposalPreview(snapshot: proposal)
                            .id("plan-proposal")
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
            .onChange(of: planProposal) { _, proposal in
                guard proposal != nil else { return }
                withAnimation(.easeOut) { scroll.scrollTo("plan-proposal", anchor: .bottom) }
            }
        }
    }

    private var isWaitingForFirstToken: Bool {
        coach.isSending && messages.last?.kind == .coach && (messages.last?.text.isEmpty ?? false)
    }

    // MARK: Footer — completion / opt-out affordances + input bar

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if let acceptanceError {
                Text(acceptanceError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            if isReady {
                readyButton
            }
            if showConversation {
                inputBar
            }
            secondaryOptOutRow
        }
        .padding(.bottom, 20)
    }

    /// Revealed as soon as the coach has created and activated a plan mid-conversation.
    private var readyButton: some View {
        Button {
            acceptPlan()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text(readyLabel)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(.glassProminent)
        .tint(.green)
        .padding(.horizontal, 24)
    }

    private func acceptPlan() {
        if proposalOnly {
            guard let planProposal else { return }
            do {
                let repository = PlanRepository(context: modelContext)
                let accepted = try repository.acceptProposal(planProposal)
                if let snapshot = repository.snapshot(of: accepted.id) {
                    Task { await SyncManager.shared.commitPlan(snapshot) }
                }
            } catch {
                acceptanceError = error.localizedDescription
                Haptics.impact(.medium)
                return
            }
        }
        Haptics.success()
        onActivePlan()
    }

    /// The ONLY opt-out from the conversation — there is no sample/starter plan anywhere in the
    /// product (domain-primitives.md §9, invariants 1/2): every real plan comes from the coach's own
    /// `plan_apply` tool. `nil` when the caller has no meaningful "skip" outcome.
    @ViewBuilder
    private var secondaryOptOutRow: some View {
        if let onSkip {
            Button(skipLabel) {
                Haptics.impact(.light)
                onSkip()
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 24)
        }
    }

    // MARK: Input

    private var inputBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                // Dictation is inserted into the existing draft. A second speech segment (or text
                // typed before tapping the mic) must not be discarded just because speech resumed.
                MicButton { text in
                    draft = VoiceInputController.mergingRecognizedText(draft, with: text)
                }

                TextField(placeholder, text: $draft, axis: .vertical)
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
    }

    // MARK: Actions

    /// Static-headline opener for every mode except onboarding, which instead gets a real coach turn
    /// — see `startOnboardingBootstrap`. Onboarding stays silent (no static line, nothing to seed)
    /// until the coach is actually configured, so the bootstrap turn is the very first thing that
    /// ever lands in `messages` for that mode.
    private func seedIfNeeded() {
        guard messages.isEmpty else { return }
        guard mode == .onboarding else {
            messages = [CoachMessage(kind: .coach, text: headline)]
            return
        }
        guard showConversation, !hasStartedOnboardingBootstrap else { return }
        hasStartedOnboardingBootstrap = true
        startOnboardingBootstrap()
    }

    /// Onboarding's real opening turn: instead of a static "Tell me about your training…" line, the
    /// coach greets and asks its own first question, exactly like any other turn — driven by a hidden
    /// stage-direction prompt that is NEVER appended to `messages` as a `.user` line (only the
    /// streamed reply is), so the transcript reads as the coach speaking first, unprompted.
    private func startOnboardingBootstrap() {
        let placeholder = CoachMessage(kind: .coach, text: "")
        messages = [placeholder]
        streamingMessageID = placeholder.id

        withAnimation(.snappy) {
            coach.converse(
                mode: mode,
                userText: "<hidden bootstrap: 'The athlete just opened onboarding. Greet in one line " +
                    "and ask what they train for and what their week looks like.'>",
                modelContext: modelContext,
                session: nil,
                onDelta: { visible in
                    replaceStreamingText(visible)
                },
                onComplete: { visible in
                    finalizeStreamingReply(fullText: visible)
                },
                onError: { message in
                    finalizeStreamingReply(replaceWithError: message)
                },
                onDiff: { confirmation in
                    messages.append(CoachMessage(kind: .diff, text: confirmation))
                },
                planProposal: planProposal,
                onPlanProposal: receiveProposal
            )
        }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !coach.isSending else { return }
        Haptics.selection()
        draft = ""
        inputFocused = false

        messages.append(CoachMessage(kind: .user, text: text))
        let placeholder = CoachMessage(kind: .coach, text: "")
        messages.append(placeholder)
        streamingMessageID = placeholder.id

        withAnimation(.snappy) {
            coach.converse(
                mode: mode,
                userText: text,
                modelContext: modelContext,
                session: nil,
                onDelta: { visible in
                    replaceStreamingText(visible)
                },
                onComplete: { visible in
                    finalizeStreamingReply(fullText: visible)
                },
                onError: { message in
                    finalizeStreamingReply(replaceWithError: message)
                },
                onDiff: { confirmation in
                    messages.append(CoachMessage(kind: .diff, text: confirmation))
                },
                planProposal: planProposal,
                onPlanProposal: receiveProposal
            )
        }
    }

    private func receiveProposal(_ proposal: PlanSnapshot) {
        planProposal = proposal
        acceptanceError = nil
    }

    private func replaceStreamingText(_ text: String) {
        guard let id = streamingMessageID, let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text = text
    }

    private func finalizeStreamingReply(fullText: String) {
        defer { streamingMessageID = nil }
        guard let id = streamingMessageID, let idx = messages.firstIndex(where: { $0.id == id }) else {
            if !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.append(CoachMessage(kind: .coach, text: fullText))
            }
            return
        }
        let resolved = fullText.isEmpty ? messages[idx].text : fullText
        if resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        } else {
            messages[idx].text = resolved
        }
    }

    private func finalizeStreamingReply(replaceWithError message: String) {
        defer { streamingMessageID = nil }
        if let id = streamingMessageID, let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].text = "Error: \(message)"
        } else {
            messages.append(CoachMessage(kind: .coach, text: "Error: \(message)"))
        }
    }
}

/// Human-readable rendering of the in-memory proposal. The underlying snapshot stays structured;
/// JSON is never part of this customer-facing surface.
private struct PlanProposalPreview: View {
    let snapshot: PlanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROPOSED PLAN")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.green)
                Text(snapshot.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                if let goal = snapshot.goal, !goal.isEmpty {
                    Text(goal)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            ForEach(Array(snapshot.sessions.enumerated()), id: \.element.id) { item in
                ProposalSessionCard(session: item.element, isFirst: item.offset == 0)
            }

            Text("Ask for changes below. Nothing is saved until you tap Use This Plan.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
    }

}

private struct ProposalSessionCard: View {
    let session: SessionSnapshot
    let isFirst: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.name).font(.headline)
                Spacer()
                Text(blockCountLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            ForEach(session.blocks, id: \.id) { block in
                ProposalBlockRow(block: block)
            }
        }
        .padding(14)
        .background(.white.opacity(isFirst ? 0.10 : 0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private var blockCountLabel: String {
        "\(session.blocks.count) block\(session.blocks.count == 1 ? "" : "s")"
    }
}

private struct ProposalBlockRow: View {
    let block: BlockSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(block.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            ForEach(block.exercises, id: \.id) { exercise in
                ProposalExerciseRow(exercise: exercise)
            }
        }
    }
}

private struct ProposalExerciseRow: View {
    let exercise: ExerciseSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(exercise.name).font(.subheadline)
            Spacer(minLength: 12)
            Text(summary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.trailing)
        }
    }

    private var summary: String {
        guard let first = exercise.sets.first else { return "No sets" }
        let count = exercise.sets.count
        if let seconds = first.seconds, let min = first.targetMinKg, let max = first.targetMaxKg {
            return "\(count) × \(seconds)s · \(kilograms(min))–\(kilograms(max)) kg"
        }
        if let seconds = first.seconds { return "\(count) × \(seconds)s" }
        if let reps = first.reps, let weight = first.weight {
            return "\(count) × \(reps) · \(Int(weight)) lb"
        }
        if let reps = first.reps { return "\(count) × \(reps)" }
        return "\(count) set\(count == 1 ? "" : "s")"
    }

    private func kilograms(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Mirrors `CoachView`'s `ThinkingIndicator` — a terse "thinking" line between the turn being sent
/// and the first streamed token.
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

/// Mirrors `CoachView`'s `CoachLineView` — plain terse lines, never bubbles or cards.
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
