import SwiftUI
import SwiftData

/// The plan library, presented as a sheet from Today (same native-surface idiom as `HistoryView`/
/// `WorkoutListView`: a grouped `List`, not the full-bleed no-cards runner treatment). Backed live
/// by SwiftData via `@Query` — creating, editing, activating, duplicating, or deleting a plan here
/// shows up on Today immediately.
struct PlansListView: View {
    @Query(sort: \PlanRecord.createdAt, order: .reverse) private var plans: [PlanRecord]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingNewPlanSheet = false
    @State private var showingGenerateSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    ContentUnavailableView(
                        "No plans yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Create a blank plan or ask the coach to generate one.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(plans) { plan in
                                NavigationLink {
                                    PlanEditorView(plan: plan)
                                } label: {
                                    PlanRow(plan: plan)
                                }
                                .swipeActions(edge: .leading) {
                                    if !plan.isActive {
                                        Button {
                                            PlanStore.setActive(plan, context: modelContext)
                                        } label: {
                                            Label("Make Active", systemImage: "checkmark.circle")
                                        }
                                        .tint(.indigo)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        PlanStore.delete(plan, context: modelContext)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        PlanStore.duplicate(plan, context: modelContext)
                                    } label: {
                                        Label("Duplicate", systemImage: "doc.on.doc")
                                    }
                                    .tint(.blue)
                                }
                            }
                        } footer: {
                            Text("Swipe a plan left to duplicate or delete it, right to make it active. Tap to edit.")
                        }
                    }
                }
            }
            .navigationTitle("Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingNewPlanSheet = true
                        } label: {
                            Label("New Plan", systemImage: "plus")
                        }
                        Button {
                            showingGenerateSheet = true
                        } label: {
                            Label("Generate from Goal…", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .accessibilityLabel("Add plan")
                }
            }
            .sheet(isPresented: $showingNewPlanSheet) { NewPlanSheet() }
            .sheet(isPresented: $showingGenerateSheet) { GeneratePlanSheet() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct PlanRow: View {
    let plan: PlanRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(plan.name)
                    .font(.body.weight(.semibold))
                if plan.isActive {
                    Text("ACTIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.indigo)
                }
            }
            Text(plan.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
