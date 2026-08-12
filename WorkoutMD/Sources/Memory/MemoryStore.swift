import Foundation
import SwiftData

// MARK: - MemoryStore
//
// See `docs/architecture/domain-primitives.md` §5. The single write/read gateway over
// `MemoryRecord` — mirrors `PlanRepository`'s shape (domain-primitives.md §4): a lightweight
// namespace-ish type over an explicit `ModelContext` the caller already has in scope (a SwiftUI
// `@Environment` or a background task's own context), not a singleton or an `@Observable`
// service. Query is substring + tag match + recency — no vector store in v1 (see §5).
struct MemoryStore {
    let context: ModelContext

    // MARK: - Write

    /// Records a new durable memory and returns its id.
    @discardableResult
    func add(text: String, tags: [String] = [], source: String = "coach") -> UUID {
        let record = MemoryRecord(text: text, tags: tags, source: source)
        context.insert(record)
        try? context.save()
        return record.id
    }

    /// Edits an existing memory. `nil` for either parameter leaves that field unchanged. Always
    /// bumps `updatedAt` so recency-ordered surfaces (`digest()`, the Settings list) reflect the
    /// edit immediately. No-op if `id` doesn't match a stored memory.
    func update(id: UUID, text: String? = nil, tags: [String]? = nil) {
        guard let record = fetchOne(id: id) else { return }
        if let text { record.text = text }
        if let tags { record.tags = tags }
        record.updatedAt = .now
        try? context.save()
    }

    func remove(id: UUID) {
        guard let record = fetchOne(id: id) else { return }
        context.delete(record)
        try? context.save()
    }

    // MARK: - Read

    /// Case-insensitive substring match on `text` when given; AND'd with a tag match (every tag in
    /// `tags` must be present on the record) when `tags` is non-empty. Sorted by `updatedAt`
    /// descending, capped by `limit` when given.
    func query(text: String? = nil, tags: [String] = [], limit: Int? = nil) -> [MemoryRecord] {
        var results = all()

        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let needle = text.lowercased()
            results = results.filter { $0.text.lowercased().contains(needle) }
        }
        if !tags.isEmpty {
            let wanted = Set(tags)
            results = results.filter { wanted.isSubset(of: Set($0.tags)) }
        }
        if let limit {
            results = Array(results.prefix(limit))
        }
        return results
    }

    /// Every stored memory, `updatedAt` descending.
    func all() -> [MemoryRecord] {
        let descriptor = FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Coach grounding

    /// A bounded, terse block of the most-recently-updated memories, for folding into coach
    /// context on every turn (domain-primitives.md §6: "whenever memories change, the digest is
    /// recomputed for the next call"). Capped to `limit` items and truncated to ~`maxChars` so a
    /// large memory store never blows the context budget. Returns `""` when there are no memories.
    func digest(limit: Int = 24, maxChars: Int = 2000) -> String {
        let recent = all().prefix(limit)
        guard !recent.isEmpty else { return "" }

        let lines = recent.map { memory -> String in
            var line = "- \(memory.text)"
            if !memory.tags.isEmpty {
                line += "  [tags: \(memory.tags.joined(separator: ", "))]"
            }
            return line
        }

        var block = (["Coach memory (durable notes about the athlete):"] + lines).joined(separator: "\n")
        if block.count > maxChars {
            block = String(block.prefix(maxChars))
        }
        return block
    }

    // MARK: - Private

    private func fetchOne(id: UUID) -> MemoryRecord? {
        var descriptor = FetchDescriptor<MemoryRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
