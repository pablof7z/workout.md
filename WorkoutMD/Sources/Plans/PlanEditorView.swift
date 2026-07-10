import SwiftUI
import SwiftData

/// Edits one `PlanRecord`'s details and its ordered blocks. Native `Form`/`List` — a native surface,
/// same idiom as `HistoryView`/`WorkoutListView`, not the full-bleed no-cards runner treatment.
/// `@Bindable` gives direct two-way bindings straight to the SwiftData model; every mutation here is
/// already live in the persisted graph, `try? modelContext.save()` just flushes it to disk promptly.
struct PlanEditorView: View {
    @Bindable var plan: PlanRecord
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $plan.name)
                TextField("Goal", text: Binding(
                    get: { plan.goal ?? "" },
                    set: { plan.goal = $0.isEmpty ? nil : $0 }
                ))
                TextField("Notes", text: Binding(
                    get: { plan.notes ?? "" },
                    set: { plan.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
            }

            Section {
                ForEach(plan.orderedBlocks) { block in
                    NavigationLink {
                        BlockEditorView(block: block)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.label).font(.body.weight(.medium))
                            Text(blockSubtitle(block)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteBlocks)
                .onMove(perform: moveBlocks)

                Button {
                    addBlock()
                } label: {
                    Label("Add Block", systemImage: "plus.circle")
                }
            } header: {
                Text("Blocks")
            } footer: {
                Text("\(plan.totalSetCount) total sets · ~\(plan.estimatedMinutes) min")
            }

            Section {
                ShareLink(
                    item: MarkdownFile(text: markdown, filename: "\(sanitizedFilename).md"),
                    preview: SharePreview("\(plan.name).md")
                ) {
                    Label("Export as Markdown", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Edit Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onDisappear { try? modelContext.save() }
    }

    private var markdown: String {
        MarkdownGenerator.renderPlan(name: plan.name, goal: plan.goal, blocks: plan.toWorkoutBlocks())
    }

    private var sanitizedFilename: String {
        plan.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
    }

    private func blockSubtitle(_ block: PlanBlockRecord) -> String {
        let exerciseCount = block.exercises.count
        let exerciseWord = exerciseCount == 1 ? "exercise" : "exercises"
        switch block.kind {
        case .straight:
            let sets = block.orderedExercises.first?.sets.count ?? 0
            return "Straight sets · \(sets) set\(sets == 1 ? "" : "s")"
        case .superset, .circuit:
            return "\(block.kind.label) · \(exerciseCount) \(exerciseWord) · \(block.rounds) rounds"
        }
    }

    private func addBlock() {
        let block = PlanBlockRecord(order: plan.blocks.count, kind: .straight, label: "New Exercise")
        let exercise = PlanExerciseRecord(order: 0, name: "New Exercise", cue: "")
        exercise.sets = [PlanSetRecord(order: 0, reps: 10, weight: nil)]
        block.exercises = [exercise]
        plan.blocks.append(block)
        try? modelContext.save()
    }

    private func deleteBlocks(at offsets: IndexSet) {
        let ordered = plan.orderedBlocks
        for index in offsets {
            modelContext.delete(ordered[index])
        }
        renumberBlocks()
        try? modelContext.save()
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var ordered = plan.orderedBlocks
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, block) in ordered.enumerated() {
            block.order = index
        }
        try? modelContext.save()
    }

    private func renumberBlocks() {
        for (index, block) in plan.orderedBlocks.enumerated() {
            block.order = index
        }
    }
}

/// Edits one block: its label, kind (straight/superset/circuit), rounds/rest (group blocks only),
/// and its ordered exercises.
struct BlockEditorView: View {
    @Bindable var block: PlanBlockRecord
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Block") {
                TextField("Label", text: $block.label)
                Picker("Kind", selection: $block.kind) {
                    ForEach(PlanBlockKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                if block.kind != .straight {
                    Stepper("Rounds: \(block.rounds)", value: $block.rounds, in: 1...10)
                    Stepper(
                        "Rest between rounds: \(block.restSeconds ?? 0)s",
                        value: Binding(get: { block.restSeconds ?? 0 }, set: { block.restSeconds = $0 == 0 ? nil : $0 }),
                        in: 0...300,
                        step: 15
                    )
                }
            }

            Section {
                ForEach(block.orderedExercises) { exercise in
                    NavigationLink {
                        ExerciseEditorView(exercise: exercise)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name.isEmpty ? "Unnamed" : exercise.name)
                            Text("\(exercise.sets.count) set\(exercise.sets.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteExercises)
                .onMove(perform: moveExercises)

                if block.kind != .straight || block.exercises.isEmpty {
                    Button {
                        addExercise()
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Exercises")
            } footer: {
                if block.kind == .straight {
                    Text("Straight-sets blocks run a single exercise.")
                }
            }
        }
        .navigationTitle(block.label.isEmpty ? "Block" : block.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onDisappear { try? modelContext.save() }
    }

    private func addExercise() {
        let exercise = PlanExerciseRecord(order: block.exercises.count, name: "New Exercise", cue: "")
        exercise.sets = (0..<max(block.rounds, 1)).map { PlanSetRecord(order: $0, reps: 10, weight: nil) }
        block.exercises.append(exercise)
        try? modelContext.save()
    }

    private func deleteExercises(at offsets: IndexSet) {
        let ordered = block.orderedExercises
        for index in offsets {
            modelContext.delete(ordered[index])
        }
        for (index, exercise) in block.orderedExercises.enumerated() {
            exercise.order = index
        }
        try? modelContext.save()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var ordered = block.orderedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in ordered.enumerated() {
            exercise.order = index
        }
        try? modelContext.save()
    }
}

/// Edits one exercise's name, coach cue, and its ordered prescribed sets.
struct ExerciseEditorView: View {
    @Bindable var exercise: PlanExerciseRecord
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section("Exercise") {
                TextField("Name", text: $exercise.name)
                TextField("Coach cue", text: $exercise.cue, axis: .vertical)
            }

            Section("Sets") {
                ForEach(exercise.orderedSets) { set in
                    SetRowEditor(set: set, onChange: { try? modelContext.save() })
                }
                .onDelete(perform: deleteSets)

                Button {
                    addSet()
                } label: {
                    Label("Add Set", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(exercise.name.isEmpty ? "Exercise" : exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onDisappear { try? modelContext.save() }
    }

    private func addSet() {
        let last = exercise.orderedSets.last
        exercise.sets.append(PlanSetRecord(order: exercise.sets.count, reps: last?.reps ?? 10, weight: last?.weight, seconds: last?.seconds))
        try? modelContext.save()
    }

    private func deleteSets(at offsets: IndexSet) {
        let ordered = exercise.orderedSets
        for index in offsets {
            modelContext.delete(ordered[index])
        }
        for (index, set) in exercise.orderedSets.enumerated() {
            set.order = index
        }
        try? modelContext.save()
    }
}

/// One editable prescribed set: reps/weight, or a timed hold — mutually exclusive, matching
/// `SetTarget`'s two cases.
private struct SetRowEditor: View {
    @Bindable var set: PlanSetRecord
    var onChange: () -> Void

    @State private var isTimed: Bool

    init(set: PlanSetRecord, onChange: @escaping () -> Void) {
        self.set = set
        self.onChange = onChange
        _isTimed = State(initialValue: set.seconds != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Type", selection: $isTimed) {
                Text("Reps").tag(false)
                Text("Timed").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: isTimed) { _, timed in
                if timed {
                    set.reps = nil
                    set.weight = nil
                    if set.seconds == nil { set.seconds = 30 }
                } else {
                    set.seconds = nil
                    if set.reps == nil { set.reps = 10 }
                }
                onChange()
            }

            if isTimed {
                Stepper(
                    "Seconds: \(set.seconds ?? 30)",
                    value: Binding(get: { set.seconds ?? 30 }, set: { set.seconds = $0; onChange() }),
                    in: 5...600,
                    step: 5
                )
            } else {
                Stepper(
                    "Reps: \(set.reps ?? 0)",
                    value: Binding(get: { set.reps ?? 0 }, set: { set.reps = $0; onChange() }),
                    in: 0...50
                )
                Stepper(
                    "Weight: \(weightLabel)",
                    value: Binding(get: { set.weight ?? 0 }, set: { set.weight = $0 == 0 ? nil : $0; onChange() }),
                    in: 0...1000,
                    step: 5
                )
            }
        }
        .padding(.vertical, 4)
    }

    private var weightLabel: String {
        guard let weight = set.weight, weight > 0 else { return "bodyweight" }
        return "\(Int(weight)) lb"
    }
}
