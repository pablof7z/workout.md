import SwiftUI

/// The full workout overview presented as a sheet from the top context strip. Because a sheet is a
/// native surface, a grouped `List` with rows is the correct idiom here — this is NOT the
/// full-bleed, no-cards runner. Rows are grouped by block, the current step is highlighted, and
/// tapping any row jumps the pager to that step.
struct WorkoutListView: View {
    let workoutName: String
    let steps: [WorkoutStep]
    let currentID: WorkoutStep.ID?
    var onSelect: (WorkoutStep.ID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.steps) { step in
                            Button {
                                onSelect(step.id)
                            } label: {
                                StepRow(step: step, isCurrent: step.id == currentID)
                            }
                            .listRowBackground(step.id == currentID ? Color.indigo.opacity(0.18) : nil)
                        }
                    }
                }
            }
            .navigationTitle(workoutName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }

    /// Groups the flat step list back into its blocks, preserving order.
    private var groups: [BlockGroup] {
        var result: [BlockGroup] = []
        for step in steps {
            if !result.isEmpty, result[result.count - 1].blockIndex == step.blockIndex {
                result[result.count - 1].steps.append(step)
            } else {
                result.append(BlockGroup(blockIndex: step.blockIndex, name: step.blockName, steps: [step]))
            }
        }
        return result
    }
}

private struct BlockGroup: Identifiable {
    let blockIndex: Int
    let name: String
    var steps: [WorkoutStep]
    var id: Int { blockIndex }
}

private struct StepRow: View {
    let step: WorkoutStep
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            badge

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .strikethrough(isSkipped, color: .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSkipped {
                Text("Skipped")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text(trailing)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
            }

            if isCurrent {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var badge: some View {
        ZStack {
            Circle()
                .fill(isCurrent ? Color.indigo : Color.secondary.opacity(0.2))
                .frame(width: 34, height: 34)
            Text(badgeLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isCurrent ? .white : .secondary)
        }
    }

    private var isSkipped: Bool {
        if case .set(let info) = step.page { return info.skipped }
        return false
    }

    private var badgeLabel: String {
        switch step.page {
        case .set(let info):
            if let short = info.miniMap?.first(where: { $0.isCurrent })?.shortLabel {
                return short
            }
            return "\(info.setNumber)"
        case .rest:
            return "R"
        }
    }

    private var title: String {
        switch step.page {
        case .set(let info): return info.exercise.name
        case .rest: return "Rest"
        }
    }

    private var subtitle: String {
        switch step.page {
        case .set(let info):
            if let round = info.round, let total = info.totalRounds {
                return "Round \(round) of \(total)"
            }
            return "Set \(info.setNumber) of \(info.totalSets)"
        case .rest(let info):
            return "After round \(info.afterRound) of \(info.totalRounds)"
        }
    }

    private var trailing: String {
        switch step.page {
        case .set(let info): return info.exercise.target.displayString
        case .rest(let info): return "\(info.seconds) sec"
        }
    }
}
