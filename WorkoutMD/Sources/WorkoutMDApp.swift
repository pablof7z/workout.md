import SwiftUI
import SwiftData

@main
struct WorkoutMDApp: App {
    /// Built explicitly (rather than via the `.modelContainer(for:)` scene modifier) so mock history
    /// can be seeded synchronously before the first frame, using the same container the rest of the
    /// app shares.
    private let container: ModelContainer = {
        let schema = Schema([
            WorkoutRecord.self,
            ExerciseRecord.self,
            SetRecord.self,
            CoachNoteRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create the WorkoutMD model container: \(error)")
        }
        MockHistory.seedIfNeeded(context: container.mainContext)
        return container
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
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
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        switch screen {
        case .today:
            TodayView {
                session = WorkoutSession()
                withAnimation(.easeInOut) { screen = .runner }
            }
        case .runner:
            SessionView { summary in
                saveToHistory()
                withAnimation(.easeInOut) { screen = .done(summary) }
            }
            .environment(session)
        case .done(let summary):
            DoneView(summary: summary) {
                withAnimation(.easeInOut) { screen = .today }
            }
        }
    }

    /// Bridges the finished `WorkoutSession` into durable SwiftData history. The live session object
    /// itself is left untouched — this only reads it to build an independent snapshot.
    private func saveToHistory() {
        let record = session.makeRecord(workoutName: MockWorkout.name, goal: MockWorkout.goal)
        modelContext.insert(record)
        try? modelContext.save()
    }
}
