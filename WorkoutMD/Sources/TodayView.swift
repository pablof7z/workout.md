import SwiftUI

/// The minimal "Today" landing screen — full-bleed, calm, one clear action: Start.
struct TodayView: View {
    var onStart: () -> Void

    var body: some View {
        ZStack {
            BackgroundView(moodKey: .bench)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Spacer()

                Text("WORKOUT.MD")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))

                Text(MockWorkout.name)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text(MockWorkout.summary)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    Haptics.impact(.medium)
                    onStart()
                } label: {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(.indigo)
                .accessibilityLabel("Start workout")
                .accessibilityHint("Begins Upper Body A")
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
    }
}
