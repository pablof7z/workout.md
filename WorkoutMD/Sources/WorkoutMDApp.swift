import SwiftUI

@main
struct WorkoutMDApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Top-level navigation between the three screens of the prototype. No NavigationStack needed —
/// this is a single linear flow: Today -> Runner -> Done -> Today.
private enum AppScreen {
    case today
    case runner
    case done(SessionSummary)
}

private struct RootView: View {
    @State private var screen: AppScreen = .today
    /// The shared source of truth for the live session, created fresh each time the user starts.
    @State private var session = WorkoutSession()

    var body: some View {
        switch screen {
        case .today:
            TodayView {
                session = WorkoutSession()
                withAnimation(.easeInOut) { screen = .runner }
            }
        case .runner:
            SessionView { summary in
                withAnimation(.easeInOut) { screen = .done(summary) }
            }
            .environment(session)
        case .done(let summary):
            DoneView(summary: summary) {
                withAnimation(.easeInOut) { screen = .today }
            }
        }
    }
}
