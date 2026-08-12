import SwiftUI
import SwiftData

@main
struct WorkoutMDApp: App {
    /// Built explicitly (rather than via the `.modelContainer(for:)` scene modifier) so the default
    /// plan seed can run synchronously before the first frame, using the same container the rest of
    /// the app shares. Exposed as `static` (`sharedModelContainer`, aliased below) so singletons with
    /// no SwiftUI environment of their own — `SyncManager`'s canonical-Markdown ingest on `pull()`,
    /// in particular (domain-primitives.md §11) — can still open a `ModelContext` against the exact
    /// same store the UI reads/writes, rather than needing a `ModelContext` threaded in from a view.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WorkoutRecord.self,
            ExerciseRecord.self,
            SetRecord.self,
            CoachNoteRecord.self,
            PlanRecord.self,
            PlanBlockRecord.self,
            PlanExerciseRecord.self,
            PlanSetRecord.self,
            // Additive-only vs. the 8 models above: `PlanSessionRecord`/`PlanRevisionRecord` are
            // brand-new models, and their only effect on existing models is two new NULLABLE columns
            // (`PlanRecord.nextSessionID`, `PlanBlockRecord.sessionID`). SwiftData's automatic
            // lightweight migration handles both cases for free — no `SchemaMigrationPlan` required.
            // See the migration-safety note on `PlanSessionRecord` (PlanModels.swift).
            PlanSessionRecord.self,
            PlanRevisionRecord.self,
            // Additive-only (Slice 2, domain-primitives.md §5): a brand-new model with no effect
            // on any existing model's columns, so this is still automatic lightweight migration —
            // no `SchemaMigrationPlan` required.
            MemoryRecord.self,
            // Additive-only (Slice 5, domain-primitives.md §8): a brand-new model with no effect on
            // any existing model's columns — the durable in-progress-workout snapshot behind
            // resume/discard on launch. Still automatic lightweight migration.
            ActiveSessionRecord.self
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
        // Idempotent code-side backfill (domain-primitives.md §12): groups any pre-existing,
        // not-yet-sessioned plan's blocks into one synthesized session. A no-op on a store that's
        // already backfilled (or has no plans yet).
        //
        // No launch-time plan seeding at all (domain-primitives.md §9): a fresh install never gets a
        // hardcoded "Upper Body A" plan — onboarding is a real coach conversation
        // (`CoachMode.onboarding`) that creates a plan via `plan_apply` from what the athlete
        // actually tells the coach. There is no sample/starter plan anywhere in product code; the
        // old `DefaultPlanSeed` now lives only as a test fixture (`Tests/WorkoutMDTests`).
        PlanMigrator.backfill(context: container.mainContext)
        return container
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.sharedModelContainer)
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
    /// One lazy CoreBluetooth connection shared by every Tindeq set in the session.
    @State private var tindeqManager = TindeqManager.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// The `inProgress` `ActiveSessionRecord` found on launch, if any — non-nil gates a full-bleed
    /// Resume/Discard prompt in front of Today (domain-primitives.md §8). Checked once via
    /// `hasCheckedForResume`, not on every `onAppear` (a `WindowGroup` scene can re-appear).
    @State private var pendingResume: ActiveSessionRecord?
    @State private var hasCheckedForResume = false
    /// Coalesces rapid mutations (e.g. a slider drag) into a single durable save ~0.4s after the
    /// last one, rather than writing SwiftData on every intermediate value — see `scheduleSave`.
    @State private var pendingSaveWorkItem: DispatchWorkItem?

    @Query(filter: #Predicate<PlanRecord> { $0.isActive == true }) private var activePlans: [PlanRecord]
    private var activePlan: PlanRecord? { activePlans.first }

    var body: some View {
        Group {
            if appSettings.hasOnboarded {
                if let pendingResume {
                    ResumePromptView(
                        onResume: { resume(from: pendingResume) },
                        onDiscard: { discardPendingResume() }
                    )
                } else {
                    content
                }
            } else {
                OnboardingView {
                    appSettings.hasOnboarded = true
                }
            }
        }
        .environment(appSettings)
        .environment(coachController)
        .environment(fabricController)
        .environment(tindeqManager)
        .onAppear(perform: checkForInProgressSession)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, case .runner = screen else { return }
            // Flush immediately rather than waiting out the debounce — the app may be about to be
            // suspended/terminated by the system.
            pendingSaveWorkItem?.cancel()
            ActiveSessionStore(context: modelContext).save(session)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .today:
            TodayView(onStart: { plan in startSession(with: plan) })
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
    /// No-op if there's no plan yet (Today already disables Start in that state). Immediately writes
    /// the first durable `ActiveSessionRecord` (domain-primitives.md §8: "the first durable
    /// representation exists before any set is logged"), then wires `onChange` so every subsequent
    /// mutation gets persisted too.
    private func startSession(with plan: PlanRecord?) {
        guard let plan else { return }
        session = WorkoutSession(steps: plan.toWorkoutSteps(), activePlan: plan, modelContext: modelContext)
        wireSessionPersistence()
        ActiveSessionStore(context: modelContext).save(session)
        withAnimation(.easeInOut) { screen = .runner }
    }

    /// Bridges the finished `WorkoutSession` into durable SwiftData history. The live session object
    /// itself is left untouched — this only reads it to build an independent snapshot. Also kicks
    /// off a GitHub commit of the session's Markdown (no-op if no token is stored yet) and, if the
    /// fabric is enabled, posts a terse kind:9 summary to the user's tenex-edge channel (no-op if the
    /// toggle is off). Marks the durable `ActiveSessionRecord` finished last, so the resume prompt
    /// never reappears for a workout that just completed normally.
    private func saveToHistory() {
        let record = session.makeRecord(workoutName: session.activePlan?.name ?? "Workout", goal: session.activePlan?.goal)
        modelContext.insert(record)
        try? modelContext.save()
        Task {
            await SyncManager.shared.commitSession(record)
        }
        fabricController.postSessionSummary(record)
        pendingSaveWorkItem?.cancel()
        ActiveSessionStore(context: modelContext).markFinished()
    }

    // MARK: - Durable active-session persistence (domain-primitives.md §8)

    /// Points `session.onChange` at a debounced save so every mutation the runner/coach makes ends
    /// up durable, not just the state at session start. Must be re-called any time `session` itself
    /// is reassigned (`startSession`, `resume`) — the hook lives on the session instance, not on
    /// `RootView`.
    private func wireSessionPersistence() {
        session.onChange = { [session] in
            scheduleSave(for: session)
        }
    }

    /// Coalesces bursts of mutations (e.g. dragging the reps/weight stepper, or a streaming coach
    /// reply) into a single `ActiveSessionStore.save` ~0.4s after the last one, rather than hitting
    /// SwiftData on every intermediate value.
    private func scheduleSave(for session: WorkoutSession) {
        pendingSaveWorkItem?.cancel()
        let store = ActiveSessionStore(context: modelContext)
        let workItem = DispatchWorkItem { store.save(session) }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    // MARK: - Resume / discard on launch

    /// Runs once per launch (guarded by `hasCheckedForResume`, since a `WindowGroup` scene's
    /// `onAppear` can fire more than once) — looks for a leftover `inProgress` `ActiveSessionRecord`
    /// from a session that never reached Done (crash, force-quit, swipe-kill).
    private func checkForInProgressSession() {
        guard !hasCheckedForResume else { return }
        hasCheckedForResume = true
        pendingResume = ActiveSessionStore(context: modelContext).currentInProgress()
    }

    /// Rebuilds the live session from `record`'s snapshot, re-wires persistence, and jumps straight
    /// into the runner — skipping Today entirely, the same way a normal `startSession` skips it.
    private func resume(from record: ActiveSessionRecord) {
        guard let restored = ActiveSessionStore(context: modelContext).loadSession(modelContext: modelContext) else {
            // Corrupt/undecodable snapshot: nothing to resume into, fall back to the normal launch
            // path rather than getting stuck on the prompt.
            pendingResume = nil
            return
        }
        session = restored
        wireSessionPersistence()
        pendingResume = nil
        screen = .runner
    }

    /// Deletes the leftover record and proceeds to the normal Today launch path.
    private func discardPendingResume() {
        ActiveSessionStore(context: modelContext).discard()
        pendingResume = nil
        screen = .today
    }
}

/// Full-bleed, no-cards Resume/Discard prompt shown in front of Today when a leftover in-progress
/// workout is found on launch (domain-primitives.md §8) — mirrors `OnboardingView`'s
/// `unconfiguredState` styling (a `BackgroundView`, plain text, `glassProminent` primary button)
/// rather than inventing a new visual language.
private struct ResumePromptView: View {
    var onResume: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        ZStack {
            BackgroundView(moodKey: .rest)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Workout in progress")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("You didn't finish your last session. Pick up where you left off, or discard it and start fresh.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)

                Button {
                    Haptics.impact(.light)
                    onResume()
                } label: {
                    Text("Resume")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(.indigo)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Button {
                    Haptics.impact(.light)
                    onDiscard()
                } label: {
                    Text("Discard")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .preferredColorScheme(.dark)
    }
}
