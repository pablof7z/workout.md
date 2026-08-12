import SwiftUI
import SwiftData

/// Idle/home is the plan library itself: one full-height plan at a time, vertically paged. Swiping
/// changes the selected/active plan but never starts a workout; Start is always an explicit tap.
struct TodayView: View {
    var onStart: (PlanRecord) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlanRecord.createdAt, order: .reverse) private var plans: [PlanRecord]
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var workouts: [WorkoutRecord]

    @State private var selectedPlanID: UUID?
    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var showingPlans = false
    @State private var showingWhatsNext = false
    @State private var showingCoach = false
    @State private var editingPlan: PlanRecord?

    var body: some View {
        ZStack(alignment: .top) {
            if plans.isEmpty {
                emptyState
            } else {
                planPager
            }
            topBar
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: selectInitialPlan)
        .onChange(of: plans.map(\.id)) { _, _ in selectInitialPlan() }
        .onChange(of: selectedPlanID) { oldValue, newValue in
            guard oldValue != newValue,
                  let newValue,
                  let plan = plans.first(where: { $0.id == newValue })
            else { return }
            PlanStore.setActive(plan, context: modelContext)
            Haptics.selection()
        }
        .sheet(isPresented: $showingHistory) { HistoryView() }
        .fullScreenCover(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingPlans) { PlansListView() }
        .sheet(isPresented: $showingWhatsNext) {
            WhatsNextView { plan in
                showingWhatsNext = false
                selectedPlanID = plan.id
            }
        }
        .sheet(isPresented: $showingCoach) { GeneratePlanSheet() }
        .sheet(item: $editingPlan) { plan in
            NavigationStack {
                PlanEditorView(plan: plan)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editingPlan = nil }
                        }
                    }
            }
        }
    }

    private var planPager: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        PlanPage(
                            plan: plan,
                            lastWorkout: lastWorkout(for: plan),
                            index: index,
                            total: plans.count,
                            onStart: {
                                PlanStore.setActive(plan, context: modelContext)
                                onStart(plan)
                            },
                            onEdit: { editingPlan = plan },
                            onAskCoach: { showingWhatsNext = true }
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .id(plan.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedPlanID)
        }
        .ignoresSafeArea()
    }

    private var emptyState: some View {
        ZStack {
            BackgroundView(moodKey: .rest).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                Text("YOUR PLANS")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.55))
                Text("Build your first plan with Coach.")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text("Describe the result you want. Review the whole plan on screen, ask for changes, then save it when it feels right.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                Button { showingCoach = true } label: {
                    Label("Create with Coach", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(.indigo)
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 28)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { showingCoach = true } label: {
                Label("New plan", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityHint("Create and revise a plan with Coach")

            Spacer()
            SettingsButton { showingSettings = true }
            HistoryButton { showingHistory = true }
            Menu {
                Button("Manage Plans", systemImage: "list.bullet.rectangle") { showingPlans = true }
                Button("Create with Coach", systemImage: "sparkles") { showingCoach = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("More plan options")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func selectInitialPlan() {
        guard !plans.isEmpty else { selectedPlanID = nil; return }
        if let selectedPlanID, plans.contains(where: { $0.id == selectedPlanID }) { return }
        selectedPlanID = plans.first(where: \.isActive)?.id ?? plans.first?.id
    }

    private func lastWorkout(for plan: PlanRecord) -> WorkoutRecord? {
        if let exact = workouts.first(where: { $0.planID == plan.id }) { return exact }
        // Older completed workouts predate durable plan identity. A same-name match is a useful
        // one-time bridge for those rows only; every newly completed workout uses the exact ID.
        return workouts.first {
            $0.planID == nil && $0.name.caseInsensitiveCompare(plan.name) == .orderedSame
        }
    }
}

private struct PlanPage: View {
    let plan: PlanRecord
    let lastWorkout: WorkoutRecord?
    let index: Int
    let total: Int
    var onStart: () -> Void
    var onEdit: () -> Void
    var onAskCoach: () -> Void

    private var session: PlanSessionRecord? { plan.resolvedSession }
    private var sessionBlocks: [PlanBlockRecord] {
        guard let session else { return plan.orderedBlocks }
        return plan.blocks(in: session)
    }
    private var exerciseNames: [String] {
        sessionBlocks.flatMap { $0.orderedExercises.map(\.name) }
    }

    var body: some View {
        ZStack {
            BackgroundView(moodKey: MoodKey.atIndex(index)).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 108)

                HStack(alignment: .center, spacing: 8) {
                    Text("WORKOUT PLAN")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                    if plan.isActive {
                        Text("CURRENT")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    Text("\(index + 1) / \(total)")
                        .font(.caption.monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.58))

                Text(plan.name)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 12)

                if let goal = plan.goal, !goal.isEmpty {
                    Text(goal)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 6)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Label("~\(plan.estimatedMinutes) min", systemImage: "clock")
                    Text("·")
                    Text("\(sessionBlocks.count) block\(sessionBlocks.count == 1 ? "" : "s")")
                    Text("·")
                    Text(lastDoneText)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.66))
                .padding(.top, 14)

                if let notes = plan.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label {
                        Text(notes).lineLimit(3)
                    } icon: {
                        Image(systemName: "note.text")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 18)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(session?.name.uppercased() ?? "NEXT SESSION")
                        .font(.caption.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(exerciseNames.prefix(4).joined(separator: "  ·  "))
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    if exerciseNames.count > 4 {
                        Text("+ \(exerciseNames.count - 4) more")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.top, 28)

                Spacer()

                HStack(spacing: 10) {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.glass)

                    Button(action: onAskCoach) {
                        Label("Ask Coach", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .buttonStyle(.glass)
                }

                Button {
                    Haptics.impact(.medium)
                    onStart()
                } label: {
                    Label("Start \(session?.name ?? plan.name)", systemImage: "play.fill")
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.glassProminent)
                .tint(.indigo)
                .padding(.top, 10)

                Text("Swipe up for another plan")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(total > 1 ? 0.45 : 0))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
    }

    private var lastDoneText: String {
        guard let lastWorkout else { return "Not done yet" }
        return "Last done \(lastWorkout.date.formatted(.relative(presentation: .named)))"
    }
}

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
    }
}

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
    }
}
