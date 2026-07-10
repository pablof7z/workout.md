import Foundation
import Observation

/// One user-supplied training-doctrine document — pasted text or an imported `.txt`/`.md` file —
/// per the product spec's §5.7 "uploaded training doctrine" promise (M7). Kept deliberately simple
/// (title + raw text): no parsing/structuring, just something the coach can read a digest of.
struct DoctrineDocument: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var content: String
    var dateAdded: Date

    init(id: UUID = UUID(), title: String, content: String, dateAdded: Date = .now) {
        self.id = id
        self.title = title
        self.content = content
        self.dateAdded = dateAdded
    }
}

/// Durable, file-backed store of the athlete's uploaded training doctrine (5/3/1 notes, hypertrophy
/// principles, whatever they paste/import), persisted as JSON in Application Support — mirrors
/// `GitHubSync`'s own pending-commit queue file pattern rather than going through SwiftData, so both
/// `SettingsView` (a normal SwiftUI environment consumer) and `CoachController` (a plain singleton
/// with no `ModelContext` of its own) can read/write it without threading a `ModelContext` through
/// call sites that don't otherwise need one.
///
/// `SettingsView`'s new "Training doctrine" section is the add/list/remove UI; `CoachController.send`
/// folds `digest()` into every turn's grounding context (gated by `AppSettings.doctrineEnabled`) so
/// "use my 5/3/1 notes" actually changes what the coach says.
@Observable
final class DoctrineStore {
    static let shared = DoctrineStore()

    private(set) var documents: [DoctrineDocument] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    private static func defaultFileURL() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkoutMD", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("doctrine-documents.json")
    }

    // MARK: - Mutation

    @discardableResult
    func add(title: String, content: String) -> DoctrineDocument? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }
        let doc = DoctrineDocument(title: trimmedTitle.isEmpty ? "Untitled doctrine" : trimmedTitle, content: trimmedContent)
        documents.append(doc)
        save()
        return doc
    }

    func remove(at offsets: IndexSet) {
        documents.remove(atOffsets: offsets)
        save()
    }

    func remove(id: UUID) {
        documents.removeAll { $0.id == id }
        save()
    }

    // MARK: - Coach grounding

    /// A bounded digest of the most-recently-added doctrine documents, folded into the coach's
    /// grounding context. Caps both document count and per-document length so a long upload can't
    /// blow out the context window of a small local model.
    func digest(maxDocs: Int = 5, maxCharsPerDoc: Int = 800) -> String {
        guard !documents.isEmpty else { return "" }
        let recent = documents.suffix(maxDocs)
        var lines = ["Training doctrine the athlete has uploaded — weight this in planning and replies:"]
        for doc in recent {
            let truncated = doc.content.count > maxCharsPerDoc
                ? String(doc.content.prefix(maxCharsPerDoc)) + "…"
                : doc.content
            lines.append("### \(doc.title)\n\(truncated)")
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        documents = (try? JSONDecoder().decode([DoctrineDocument].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
