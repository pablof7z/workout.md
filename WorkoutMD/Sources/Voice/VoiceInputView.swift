import SwiftUI

/// The reusable voice-dictation overlay (domain-primitives.md §10) driven by `VoiceInputController`.
/// Full-bleed dark, no cards — matches `CoachView`/`OnboardingView`'s aesthetic exactly, with Liquid
/// Glass reserved for the floating controls. Presented full-screen from `MicButton`; the coach never
/// sees this view at all — it only ever receives the plain text handed back through `onSubmit`.
struct VoiceInputView: View {
    var controller: VoiceInputController
    /// Background mood to match whatever surface presented this (Coach chat's current exercise mood,
    /// or `.rest` for onboarding) — purely cosmetic continuity, no behavioral effect.
    var moodKey: MoodKey = .rest
    /// Called with the user-edited final transcript when they tap "Use" — the ONLY way text leaves
    /// this view. The caller (a `MicButton` embedded in an input bar) drops it straight into its
    /// existing `draft` field, same as if it had been typed.
    var onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reviewText = ""
    @FocusState private var reviewFocused: Bool

    var body: some View {
        ZStack {
            BackgroundView(moodKey: moodKey)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                closeRow
                Spacer()
                content
                Spacer()
                controls
            }
        }
        .onChange(of: controller.phase) { _, phase in
            if case .review(let text) = phase {
                reviewText = text
            }
        }
    }

    // MARK: Close

    private var closeRow: some View {
        HStack {
            Spacer()
            Button {
                Haptics.impact(.light)
                controller.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Cancel dictation")
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
    }

    // MARK: Phase content

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle, .authorizing:
            recordingPrompt(active: false)
        case .recording:
            recordingPrompt(active: true)
        case .transcribing:
            transcribingState
        case .review:
            reviewState
        case .error(let message):
            errorState(message)
        }
    }

    private func recordingPrompt(active: Bool) -> some View {
        VStack(spacing: 18) {
            RecordingIndicator(active: active)
            Text(active ? "Listening…" : "Starting…")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            if controller.supportsPartials {
                Text(controller.partialText.isEmpty ? " " : controller.partialText)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
                    .frame(minHeight: 24)
            }
        }
    }

    private var transcribingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white.opacity(0.8))
            Text("Transcribing…")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private var reviewState: some View {
        VStack(spacing: 14) {
            Text("Review")
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.55))
            TextEditor(text: $reviewText)
                .scrollContentBackground(.hidden)
                .font(.callout)
                .foregroundStyle(.white)
                .tint(.indigo)
                .focused($reviewFocused)
                .frame(minHeight: 120, maxHeight: 260)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 24)
        }
        .onAppear { reviewFocused = true }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            switch controller.phase {
            case .idle, .authorizing, .transcribing:
                EmptyView()

            case .recording:
                HStack(spacing: 12) {
                    cancelButton
                    Spacer()
                    Button {
                        Haptics.impact(.medium)
                        Task { await controller.finish() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.indigo).interactive(), in: .capsule)
                }

            case .review:
                HStack(spacing: 12) {
                    cancelButton
                    Spacer()
                    Button {
                        Haptics.success()
                        let text = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
                        controller.cancel()
                        dismiss()
                        guard !text.isEmpty else { return }
                        onSubmit(text)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Use")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.indigo).interactive(), in: .capsule)
                    .disabled(reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

            case .error:
                HStack(spacing: 12) {
                    cancelButton
                    Spacer()
                    Button {
                        Haptics.impact(.light)
                        Task { await controller.start() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.indigo).interactive(), in: .capsule)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var cancelButton: some View {
        Button {
            Haptics.impact(.light)
            controller.cancel()
            dismiss()
        } label: {
            Text("Cancel")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 18)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// A small pulsing dot standing in for a waveform — active while `phase == .recording`, dimmed and
/// still otherwise. Intentionally terse rather than a full amplitude waveform (no audio-level metering
/// is exposed by either `TranscriptionProvider` implementation).
private struct RecordingIndicator: View {
    let active: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(active ? Color.red.opacity(0.85) : Color.white.opacity(0.3))
            .frame(width: 22, height: 22)
            .scaleEffect(active && pulse ? 1.6 : 1.0)
            .opacity(active && pulse ? 0.0 : 1.0)
            .overlay(
                Circle()
                    .fill(active ? Color.red.opacity(0.85) : Color.white.opacity(0.3))
                    .frame(width: 22, height: 22)
            )
            .onAppear { startPulseIfNeeded() }
            .onChange(of: active) { _, _ in startPulseIfNeeded() }
            .accessibilityHidden(true)
    }

    private func startPulseIfNeeded() {
        guard active else {
            pulse = false
            return
        }
        withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

/// The mic affordance `CoachView`/`OnboardingView` embed next to their text field. Owns its own
/// `VoiceInputController` and presentation state — a self-contained "tap to dictate" button that
/// hands the caller plain text via `onSubmit`, same shape as every other input-bar action here.
struct MicButton: View {
    var moodKey: MoodKey = .rest
    var onSubmit: (String) -> Void

    @State private var controller = VoiceInputController()
    @State private var isPresented = false

    var body: some View {
        Button {
            Haptics.impact(.light)
            isPresented = true
            Task { await controller.start() }
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Dictate")
        .fullScreenCover(isPresented: $isPresented) {
            VoiceInputView(controller: controller, moodKey: moodKey, onSubmit: onSubmit)
        }
    }
}
