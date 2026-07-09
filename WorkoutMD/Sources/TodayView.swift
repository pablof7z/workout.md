import SwiftUI

/// The minimal "Today" landing screen — full-bleed, calm, one clear action: Start.
struct TodayView: View {
    var onStart: () -> Void

    var body: some View {
        ZStack {
            BackgroundView(moodKey: .bench)
                .ignoresSafeArea()
                .onAppear {
                    // Proof that the WorkoutCore UniFFI object (not just the
                    // free function) round-trips through the FFI boundary.
                    let core = WorkoutCore()
                    print("[workout-core] \(core.greeting()) — echo(\"ping\") = \(core.echo(message: "ping"))")
                }

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

            // Subtle proof-of-life for the Rust core linked via UniFFI — not
            // part of the product design, just visible confirmation that the
            // Swift shell is actually calling into the compiled Rust core.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("core v\(coreVersion())")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.trailing, 12)
                        .padding(.bottom, 6)
                }
            }
        }
    }
}
