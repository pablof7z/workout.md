import SwiftUI

/// Terse, calm completion screen. No confetti, no streaks — just a summary and a way back to Today.
struct DoneView: View {
    let summary: SessionSummary
    var onDone: () -> Void

    var body: some View {
        ZStack {
            BackgroundView(moodKey: .rest)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text("Session complete")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                VStack(spacing: 6) {
                    Text("\(summary.loggedSets) of \(summary.totalSets) sets logged")
                    Text("Avg effort: \(summary.averageEffortLabel)")
                }
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityElement(children: .combine)

                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                    Text("Saved as Markdown")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

                Spacer()

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.glassProminent)
                .tint(.indigo)
                .accessibilityLabel("Done, return to Today")
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            Haptics.success()
        }
    }
}
