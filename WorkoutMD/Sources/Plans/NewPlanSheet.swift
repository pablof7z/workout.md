import SwiftUI
import SwiftData

/// Creates a plan blank, duplicated from an existing plan, or built from a past completed session
/// — the non-coach creation paths (see `GeneratePlanSheet` for the coach-generated one).
struct NewPlanSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlanRecord.createdAt, order: .reverse) private var existingPlans: [PlanRecord]
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var sessions: [WorkoutRecord]

    private enum Source: String, CaseIterable, Identifiable {
        case blank = "Blank"
        case fromPlan = "Duplicate Plan"
        case fromSession = "Past Session"
        var id: String { rawValue }
    }

    @State private var source: Source = .blank
    @State private var name = ""
    @State private var goal = ""
    @State private var selectedPlanID: PersistentIdentifier?
    @State private var selectedSessionID: PersistentIdentifier?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Start from", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Goal", text: $goal)
                }

                if source == .fromPlan {
                    Section("Duplicate") {
                        if existingPlans.isEmpty {
                            Text("No plans to duplicate yet.").foregroundStyle(.secondary)
                        } else {
                            Picker("Plan", selection: $selectedPlanID) {
                                ForEach(existingPlans) { plan in
                                    Text(plan.name).tag(Optional(plan.persistentModelID))
                                }
                            }
                        }
                    }
                } else if source == .fromSession {
                    Section("Session") {
                        if sessions.isEmpty {
                            Text("No past sessions yet.").foregroundStyle(.secondary)
                        } else {
                            Picker("Session", selection: $selectedSessionID) {
                                ForEach(sessions) { session in
                                    Text("\(session.name) — \(session.date.formatted(date: .abbreviated, time: .omitted))")
                                        .tag(Optional(session.persistentModelID))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(!canCreate)
                }
            }
            .onAppear {
                selectedPlanID = existingPlans.first?.persistentModelID
                selectedSessionID = sessions.first?.persistentModelID
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var canCreate: Bool {
        switch source {
        case .blank: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .fromPlan: return selectedPlanID != nil
        case .fromSession: return selectedSessionID != nil
        }
    }

    private func create() {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespaces)
        switch source {
        case .blank:
            PlanStore.createBlank(name: name, goal: trimmedGoal.isEmpty ? nil : trimmedGoal, context: modelContext)

        case .fromPlan:
            guard let id = selectedPlanID, let plan = existingPlans.first(where: { $0.persistentModelID == id }) else { return }
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            PlanStore.duplicate(plan, newName: trimmedName.isEmpty ? nil : trimmedName, context: modelContext)

        case .fromSession:
            guard let id = selectedSessionID, let session = sessions.first(where: { $0.persistentModelID == id }) else { return }
            let created = PlanStore.createFromSession(session, context: modelContext)
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            if !trimmedName.isEmpty { created.name = trimmedName }
            if !trimmedGoal.isEmpty { created.goal = trimmedGoal }
            try? modelContext.save()
        }
        dismiss()
    }
}
