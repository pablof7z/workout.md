import SwiftUI

/// The minimal "Today" landing screen — full-bleed, calm, one clear action: Start, plus the
/// prominent M5 "What should I do next?" entry. Shows the ACTIVE plan's name/summary (there is
/// always exactly one active `PlanRecord` once the default seed has run) rather than a hardcoded
/// workout. A small glass Plans/History/Settings row sits in the top-trailing corner — the one
/// concession to secondary navigation on an otherwise single-purpose screen.
struct TodayView: View {
    var activePlan: PlanRecord?
    var onStart: () -> Void
    var onSelectPlan: (PlanRecord) -> Void

    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var showingPlans = false
    @State private var showingWhatsNext = false

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
                HStack {
                    Spacer()
                    SettingsButton { showingSettings = true }
                    PlansButton { showingPlans = true }
                    HistoryButton { showingHistory = true }
                }

                Spacer()

                Text("WORKOUT.MD")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))

                Text(activePlan?.name ?? "No plan yet")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text(activePlan?.summary ?? "Create a plan to get started")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Button {
                    Haptics.impact(.light)
                    showingWhatsNext = true
                } label: {
                    Label("What should I do next?", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.glass)
                .tint(.white)
                .accessibilityHint("Asks the coach to propose or repair the next session")

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
                .disabled(activePlan == nil)
                .accessibilityLabel("Start workout")
                .accessibilityHint(activePlan.map { "Begins \($0.name)" } ?? "No active plan yet")
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)

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
        .sheet(isPresented: $showingHistory) {
            HistoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingPlans) {
            PlansListView()
        }
        .sheet(isPresented: $showingWhatsNext) {
            WhatsNextView { plan in
                showingWhatsNext = false
                onSelectPlan(plan)
            }
        }
    }
}

/// Small floating glass icon button that opens past-session History.
private struct HistoryButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("History")
        .accessibilityHint("View past workout sessions")
    }
}

/// Small floating glass icon button that opens the Plans library (select/create/edit/duplicate).
private struct PlansButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Plans")
        .accessibilityHint("View, select, create, or edit your workout plans")
    }
}

/// Small floating glass icon button that opens Settings (coach provider/model, GitHub sync, goals).
private struct SettingsButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Settings")
        .accessibilityHint("Configure the coach and sync")
    }
}
