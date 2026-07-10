import SwiftUI
import SwiftData

@main
struct WorkoutMDApp: App {
    /// Built explicitly (rather than via the `.modelContainer(for:)` scene modifier) so the default
    /// plan seed can run synchronously before the first frame, using the same container the rest of
    /// the app shares.
    private let container: ModelContainer = {
        let schema = Schema([
            WorkoutRecord.self,
            ExerciseRecord.self,
            SetRecord.self,
            CoachNoteRecord.self,
            PlanRecord.self,
            PlanBlockRecord.self,
            PlanExerciseRecord.self,
            PlanSetRecord.self
        ])
        // Explicitly opt this local SwiftData store out of SwiftData's automatic CloudKit mirroring.
        // Without this, `ModelConfiguration`'s default `cloudKitDatabase: .automatic` detects the
        // app's iCloud container entitlement (added for `ICloudSync`'s Documents mirror below) and
        // tries to stand up an `NSPersistentCloudKitContainer` — which then fails fast at launch
        // because this schema uses unique constraints and non-optional attributes CloudKit doesn't
        // support. `ICloudSync` mirrors the rendered Markdown by hand instead, so SwiftData itself
        // has no business talking to CloudKit at all.
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create the WorkoutMD model container: \(error)")
        }
        PlanStore.seedDefaultIfNeeded(context: container.mainContext)
        return container
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                SyncManager.shared.appDidBecomeActive()
            case .background:
                SyncManager.shared.appDidEnterBackground()
            default:
                break
            }
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
    /// The shared source of truth for the live session, created fresh each time the user starts —
    /// always built from the ACTIVE `PlanRecord`, never a hardcoded workout (see `startSession`).
    @State private var session = WorkoutSession()
    /// App-wide, once-per-launch: the coach's Settings-backed preferences and the live coach engine
    /// itself. Both are injected here (rather than per-screen) so Today's gear button, the Coach
    /// screen, and Settings all share the exact same `CoachController`/`CoachEngine` instance.
    @State private var appSettings = AppSettings.shared
    @State private var coachController = CoachController()
    /// Same singleton `CoachController` reaches for by default (`fabric: FabricController = .shared`)
    /// so both share the one live `NostrCoach` instance/subscription.
    @State private var fabricController = FabricController.shared
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<PlanRecord> { $0.isActive == true }) private var activePlans: [PlanRecord]
    private var activePlan: PlanRecord? { activePlans.first }

    var body: some View {
        Group {
            if appSettings.hasOnboarded {
                content
            } else {
                OnboardingView {
                    appSettings.hasOnboarded = true
                }
            }
        }
        .environment(appSettings)
        .environment(coachController)
        .environment(fabricController)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .today:
            TodayView(
                activePlan: activePlan,
                onStart: { startSession(with: activePlan) },
                onSelectPlan: { plan in
                    PlanStore.setActive(plan, context: modelContext)
                    startSession(with: plan)
                }
            )
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

    /// Builds a fresh `WorkoutSession` from `plan`'s prescribed steps and switches to the runner.
    /// No-op if there's no plan yet (Today already disables Start in that state).
    private func startSession(with plan: PlanRecord?) {
        guard let plan else { return }
        session = WorkoutSession(steps: plan.toWorkoutSteps(), activePlan: plan, modelContext: modelContext)
        withAnimation(.easeInOut) { screen = .runner }
    }

    /// Bridges the finished `WorkoutSession` into durable SwiftData history. The live session object
    /// itself is left untouched — this only reads it to build an independent snapshot. Also kicks
    /// off a GitHub commit of the session's Markdown (no-op if no token is stored yet) and, if the
    /// fabric is enabled, posts a terse kind:9 summary to the user's tenex-edge channel (no-op if the
    /// toggle is off).
    private func saveToHistory() {
        let record = session.makeRecord(workoutName: session.activePlan?.name ?? "Workout", goal: session.activePlan?.goal)
        modelContext.insert(record)
        try? modelContext.save()
        Task {
            await SyncManager.shared.commitSession(record)
        }
        fabricController.postSessionSummary(record)
    }
}
