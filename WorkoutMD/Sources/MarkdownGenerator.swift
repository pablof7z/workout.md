import Foundation

/// Renders completed sessions and workout plans into clean, portable Markdown — the artifact this
/// app treats as the durable, syncable record of what was planned and what actually happened
/// (product spec §9). These are pure functions over plain data (SwiftData `@Model` records, or the
/// in-memory plan models from `Models.swift`), so they're reusable and unit-testable without a
/// `ModelContext` or a live `WorkoutSession`.
enum MarkdownGenerator {

    // MARK: - Completed session → Markdown

    /// Renders a finished, persisted session: front-matter, prescribed-vs-actual per exercise,
    /// a terse summary, and the coach transcript/adjustments.
    static func renderSession(_ record: WorkoutRecord) -> String {
        var lines: [String] = []

        lines.append("---")
        lines.append("date: \(isoFormatter.string(from: record.date))")
        lines.append("workout: \(record.name)")
        if let goal = record.goal, !goal.isEmpty {
            lines.append("goal: \(goal)")
        }
        lines.append("sets_logged: \(record.loggedSets)/\(record.totalSets)")
        if let averageRPE = record.averageRPE {
            lines.append("avg_rpe: \(oneDecimal(averageRPE))")
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(record.name)")
        lines.append("")

        let subtitleGoal = record.goal.map { " · \($0)" } ?? ""
        lines.append("_\(displayDate(record.date))\(subtitleGoal)_")
        lines.append("")

        let exercises = record.exercises.sorted { $0.order < $1.order }
        for exercise in exercises {
            lines.append(contentsOf: renderExercise(exercise))
        }

        lines.append("## Summary")
        lines.append("")
        lines.append("- Sets logged: \(record.loggedSets) of \(record.totalSets)")
        if let averageRPE = record.averageRPE {
            lines.append("- Average effort: \(EffortScale.label(for: averageRPE)) · RPE \(oneDecimal(averageRPE))")
        } else {
            lines.append("- Average effort: —")
        }
        let deviations = exercises.flatMap(\.sets).filter(\.isDeviation).count
        lines.append("- Deviations from plan: \(deviations)")
        lines.append("")

        let notes = record.coachNotes.sorted { $0.order < $1.order }
        if !notes.isEmpty {
            lines.append("## Coach Notes")
            lines.append("")
            for note in notes {
                lines.append(renderNoteLine(note))
            }
            lines.append("")
        }

        return joined(lines)
    }

    private static func renderExercise(_ exercise: ExerciseRecord) -> [String] {
        var lines: [String] = []
        let heading: String
        if let groupLabel = exercise.groupLabel {
            heading = "\(groupLabel) — \(exercise.name)"
        } else {
            heading = exercise.name
        }
        lines.append("## \(heading)")
        lines.append("")
        lines.append("| Set | Prescribed | Actual | RPE | Notes |")
        lines.append("|---|---|---|---|---|")

        for set in exercise.sets.sorted(by: { $0.order < $1.order }) {
            var noteParts: [String] = []
            if set.substituted {
                noteParts.append("Substituted\(set.substitutedName.map { ": \($0)" } ?? "")")
            }
            if let setNotes = set.notes, !setNotes.isEmpty {
                noteParts.append(setNotes)
            }
            let notesCell = noteParts.joined(separator: "; ")
            let rpeCell = set.rpe.map { oneDecimal($0) } ?? "—"
            lines.append("| \(set.label) | \(set.prescribedDisplay) | \(set.actualDisplay) | \(rpeCell) | \(notesCell) |")
        }

        lines.append("")
        return lines
    }

    private static func renderNoteLine(_ note: CoachNoteRecord) -> String {
        let scope = note.exerciseName.map { "**\($0)** — " } ?? ""
        switch note.kind {
        case .coach:
            return "- \(scope)\"\(note.text)\""
        case .user:
            return "- \(scope)_\(note.text)_ (user)"
        case .diff:
            return "- \(scope)Applied: \(note.text)"
        }
    }

    // MARK: - Plan → Markdown

    /// Renders a workout PLAN (not yet performed) to Markdown: goal, and each block's prescribed
    /// work, so a plan can be synced/exported the same way a completed log can.
    static func renderPlan(name: String, goal: String? = nil, blocks: [WorkoutBlock]) -> String {
        var lines: [String] = []

        lines.append("---")
        lines.append("workout: \(name)")
        if let goal, !goal.isEmpty {
            lines.append("goal: \(goal)")
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(name)")
        if let goal, !goal.isEmpty {
            lines.append("")
            lines.append("_\(goal)_")
        }
        lines.append("")

        for block in blocks {
            lines.append(contentsOf: renderBlock(block))
        }

        return joined(lines)
    }

    private static func renderBlock(_ block: WorkoutBlock) -> [String] {
        var lines: [String] = []

        switch block.kind {
        case .straightSets(let exercise, let sets):
            lines.append("## \(block.name)")
            lines.append("")
            lines.append("- \(sets) x \(exercise.target.displayString)")
            lines.append("- Cue: \(exercise.cue)")
            lines.append("")

        case .group(let kind, let label, let letterPrefix, let exercises, let rounds, let restSeconds):
            lines.append("## \(label) (\(kind.label)) — \(rounds) rounds")
            lines.append("")
            for (index, exercise) in exercises.enumerated() {
                let prefix = letterPrefix.map { "\($0)\(index + 1) " } ?? ""
                lines.append("- \(prefix)\(exercise.name): \(exercise.target.displayString) — \(exercise.cue)")
            }
            if let restSeconds {
                lines.append("- Rest between rounds: \(restSeconds) sec")
            }
            lines.append("")
        }

        return lines
    }

    // MARK: - Formatting helpers (pure, unit-testable)

    /// Formats a value to one decimal place, e.g. `7.5`. Exposed as a standalone helper so it (and
    /// the summary lines that use it) can be exercised without a full `WorkoutRecord`.
    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Human-readable "yyyy-MM-dd HH:mm" for the front-matter subtitle line.
    static func displayDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func joined(_ lines: [String]) -> String {
        var text = lines.joined(separator: "\n")
        while text.hasSuffix("\n") {
            text.removeLast()
        }
        return text + "\n"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
