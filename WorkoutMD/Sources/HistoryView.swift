import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Past-sessions list, presented as a sheet from a small glass corner button on Today (same idiom
/// as `WorkoutListView`: a native surface gets a native grouped `List`, not the full-bleed no-cards
/// runner treatment). Backed live by SwiftData via `@Query`, so a session saved at Done shows up
/// here immediately.
struct HistoryView: View {
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Finish a session to see it here.")
                    )
                } else {
                    List {
                        SyncDebugSection()
                        ForEach(records) { record in
                            NavigationLink {
                                HistoryDetailView(record: record)
                            } label: {
                                HistoryRow(record: record)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
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
}

private struct HistoryRow: View {
    let record: WorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.name)
                    .font(.body.weight(.semibold))
                if record.isMock {
                    Text("SAMPLE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(record.oneLineSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Minimal, temporary debug affordance for GitHub sync — no Settings screen exists yet, so this is
/// the one place to see sync status and trigger a pull by hand. Hidden behind nothing fancy: just a
/// section at the top of History, gone once a real Settings screen lands.
private struct SyncDebugSection: View {
    @State private var manager = SyncManager.shared

    var body: some View {
        Section("GitHub Sync (debug)") {
            LabeledContent("Status", value: manager.status.label)
            LabeledContent("Signed in", value: manager.isAuthenticated ? "Yes" : "No token")
            if let lastSyncedAt = manager.lastSyncedAt {
                LabeledContent("Last synced", value: lastSyncedAt.formatted(date: .omitted, time: .shortened))
            }
            if manager.pendingCommitCount > 0 {
                LabeledContent("Pending commits", value: "\(manager.pendingCommitCount)")
            }
            Button {
                Task { await manager.pullNow() }
            } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!manager.isAuthenticated)
        }
    }
}

/// One session's detail: summary, per-exercise prescribed-vs-actual, the coach transcript, and the
/// rendered Markdown with a share/export action for the `.md` file.
struct HistoryDetailView: View {
    let record: WorkoutRecord

    private var markdown: String { MarkdownGenerator.renderSession(record) }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Date", value: record.date.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Goal", value: record.goal?.isEmpty == false ? record.goal! : "—")
                LabeledContent("Sets logged", value: "\(record.loggedSets) of \(record.totalSets)")
                if let averageRPE = record.averageRPE {
                    LabeledContent("Avg RPE", value: MarkdownGenerator.oneDecimal(averageRPE))
                }
            }

            ForEach(record.exercises.sorted(by: { $0.order < $1.order })) { exercise in
                Section(exercise.groupLabel.map { "\($0) — \(exercise.name)" } ?? exercise.name) {
                    ForEach(exercise.sets.sorted(by: { $0.order < $1.order })) { set in
                        SetRow(set: set)
                    }
                }
            }

            if !record.coachNotes.isEmpty {
                Section("Coach") {
                    ForEach(record.coachNotes.sorted(by: { $0.order < $1.order })) { note in
                        Text(note.text)
                            .font(.footnote)
                            .foregroundStyle(note.kind == .diff ? Color.green : .primary)
                    }
                }
            }

            Section("Markdown") {
                Text(markdown)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: MarkdownFile(text: markdown, filename: "\(sanitizedFilename).md"),
                    preview: SharePreview("\(record.name).md")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share Markdown")
            }
        }
    }

    private var sanitizedFilename: String {
        record.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}

private struct SetRow: View {
    let set: SetRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(set.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if set.skipped {
                    Text("Skipped")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if let rpe = set.rpe {
                    Text("RPE \(MarkdownGenerator.oneDecimal(rpe))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(set.prescribedDisplay) → \(set.actualDisplay)")
                .font(.caption)
                .foregroundStyle(set.isDeviation ? .orange : .secondary)
            if let notes = set.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A plain-text payload that shares/exports as a named `.md` file via `ShareLink`.
struct MarkdownFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName { file in file.filename }
    }
}
