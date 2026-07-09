import SwiftUI

/// The scripted mock coach, scoped to the current exercise. Full-bleed dark (same aesthetic as the
/// runner — NOT a sheet, NOT web cards). The user types a plain-language note; a local keyword
/// policy appends a terse, dry coach reply and applies a concrete change to the shared
/// `WorkoutSession`, shown as a distinct applied-diff line. Those edits reflect on the runner's
/// upcoming pages. The coach voice is dry and direct — no pep talk.
struct CoachView: View {
    @Environment(WorkoutSession.self) private var session
    var onBackToRunner: () -> Void

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var exerciseName: String { session.currentExerciseName ?? "This exercise" }
    private var moodKey: MoodKey { session.currentStep?.moodKey ?? .rest }
    private var messages: [CoachMessage] { session.transcript(for: exerciseName) }

    var body: some View {
        ZStack {
            BackgroundView(moodKey: moodKey)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                transcript
                deloadChip
                inputBar
            }
        }
        .onAppear { session.seedTranscriptIfNeeded(for: exerciseName) }
        .onChange(of: exerciseName) { _, newValue in
            session.seedTranscriptIfNeeded(for: newValue)
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
        }
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
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send to coach")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Haptics.selection()
        withAnimation(.snappy) {
            session.sendCoachMessage(text)
        }
        draft = ""
        inputFocused = false
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
