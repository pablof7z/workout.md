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

    /// Adds a block into the plan's resolved session, creating one first if this plan has none yet
    /// (e.g. a not-yet-backfilled legacy plan opened before `PlanMigrator.backfill` ran).
    private func addBlock() {
        let session: PlanSessionRecord
        if let resolved = plan.resolvedSession {
            session = resolved
        } else {
            let created = PlanSessionRecord(order: 0, name: "Workout")
            created.plan = plan
            plan.sessions.append(created)
            plan.nextSessionID = created.id
            session = created
        }
        let block = PlanBlockRecord(order: plan.blocks(in: session).count, kind: .straight, label: "New Exercise", sessionID: session.id)
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
        exercise.sets.append(PlanSetRecord(
            order: exercise.sets.count,
            reps: last?.reps ?? 10,
            weight: last?.weight,
            seconds: last?.seconds,
            targetMinKg: last?.targetMinKg,
            targetMaxKg: last?.targetMaxKg
        ))
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

/// One editable prescribed set: reps/weight, a plain timed hold, or a Tindeq force-corridor hold.
private struct SetRowEditor: View {
    @Bindable var set: PlanSetRecord
    var onChange: () -> Void

    private enum TargetKind: String, CaseIterable, Identifiable {
        case reps = "Reps"
        case timed = "Timed"
        case tindeq = "Tindeq"

        var id: Self { self }
    }

    @State private var targetKind: TargetKind

    init(set: PlanSetRecord, onChange: @escaping () -> Void) {
        self.set = set
        self.onChange = onChange
        _targetKind = State(initialValue: {
            if set.targetMinKg != nil, set.targetMaxKg != nil { return .tindeq }
            return set.seconds == nil ? .reps : .timed
        }())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Type", selection: $targetKind) {
                ForEach(TargetKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: targetKind) { _, kind in
                switch kind {
                case .reps:
                    set.seconds = nil
                    set.targetMinKg = nil
                    set.targetMaxKg = nil
                    if set.reps == nil { set.reps = 10 }
                case .timed:
                    set.reps = nil
                    set.weight = nil
                    set.targetMinKg = nil
                    set.targetMaxKg = nil
                    if set.seconds == nil { set.seconds = 30 }
                case .tindeq:
                    set.reps = nil
                    set.weight = nil
                    if set.seconds == nil { set.seconds = 7 }
                    if set.targetMinKg == nil { set.targetMinKg = 30 }
                    if set.targetMaxKg == nil { set.targetMaxKg = 34 }
                }
                onChange()
            }

            if targetKind == .timed || targetKind == .tindeq {
                Stepper(
                    "Seconds: \(set.seconds ?? 30)",
                    value: Binding(get: { set.seconds ?? 30 }, set: { set.seconds = $0; onChange() }),
                    in: 1...600,
                    step: targetKind == .tindeq ? 1 : 5
                )
            }

            if targetKind == .tindeq {
                Stepper(
                    "Target minimum: \(kilograms(set.targetMinKg ?? 30)) kg",
                    value: Binding(
                        get: { set.targetMinKg ?? 30 },
                        set: {
                            set.targetMinKg = min($0, set.targetMaxKg ?? $0)
                            onChange()
                        }),
                    in: 0...500,
                    step: 0.5
                )
                Stepper(
                    "Target maximum: \(kilograms(set.targetMaxKg ?? 34)) kg",
                    value: Binding(
                        get: { set.targetMaxKg ?? 34 },
                        set: {
                            set.targetMaxKg = max($0, set.targetMinKg ?? $0)
                            onChange()
                        }),
                    in: 0...500,
                    step: 0.5
                )
            } else if targetKind == .reps {
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

    private func kilograms(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
