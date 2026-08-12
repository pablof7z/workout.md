import XCTest
import SwiftData
@testable import WorkoutMD

/// Unit tests for the general durable-memory primitive family (domain-primitives.md §5):
/// `MemoryStore`'s add/update/remove/query/digest operations. Uses an in-memory `ModelContainer` —
/// see `makeContext()` — so every test starts from a clean store. `@testable import WorkoutMD` is
/// required because these types live on `MemoryRecord`, which transitively pulls in the whole app.
final class MemoryStoreTests: XCTestCase {

    // MARK: - Fixture

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutRecord.self,
            ExerciseRecord.self,
            SetRecord.self,
            CoachNoteRecord.self,
            PlanRecord.self,
            PlanBlockRecord.self,
            PlanExerciseRecord.self,
            PlanSetRecord.self,
            PlanSessionRecord.self,
            PlanRevisionRecord.self,
            MemoryRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    // MARK: - 1. add / query

    func testAddThenQueryBySubstringReturnsIt() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)

        store.add(text: "Prefers training in the evening", tags: ["schedule"], source: "coach")
        store.add(text: "Recovering from a shoulder tweak", tags: ["injury"], source: "coach")

        let results = store.query(text: "shoulder")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "Recovering from a shoulder tweak")
    }

    func testQueryBySubstringIsCaseInsensitive() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)
        store.add(text: "Dislikes Burpees", tags: ["dislike"])

        XCTAssertEqual(store.query(text: "burpees").count, 1)
        XCTAssertEqual(store.query(text: "BURPEES").count, 1)
    }

    func testAddThenQueryByTagReturnsIt() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)

        store.add(text: "Primary goal: Hypertrophy", tags: ["goal"], source: "migrated")
        store.add(text: "Prefers sessions around 45 minutes.", tags: ["schedule"], source: "migrated")

        let results = store.query(tags: ["goal"])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.text, "Primary goal: Hypertrophy")
    }

    func testQueryByMultipleTagsRequiresAllOfThem() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)

        store.add(text: "A", tags: ["a", "b"])
        store.add(text: "B", tags: ["a"])

        XCTAssertEqual(store.query(tags: ["a", "b"]).count, 1)
        XCTAssertEqual(store.query(tags: ["a"]).count, 2)
    }

    // MARK: - 2. add/update/remove lifecycle

    func testAddUpdateRemoveLifecycle() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)

        let id = store.add(text: "Original text", tags: ["a"], source: "user")
        XCTAssertEqual(store.all().count, 1)

        store.update(id: id, text: "Edited text")
        let afterUpdate = store.all().first
        XCTAssertEqual(afterUpdate?.text, "Edited text")
        XCTAssertEqual(afterUpdate?.tags, ["a"], "tags left unchanged when nil is passed")
        XCTAssertEqual(afterUpdate?.source, "user", "source is never touched by update")

        store.remove(id: id)
        XCTAssertTrue(store.all().isEmpty)
    }

    func testUpdateBumpsUpdatedAtAndLeavesOtherFieldsAlone() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)

        let id = store.add(text: "Text", tags: ["x"], source: "coach")
        let original = try XCTUnwrap(store.all().first)
        let originalUpdatedAt = original.updatedAt
        let originalCreatedAt = original.createdAt

        // Ensure a measurable time delta before the update.
        Thread.sleep(forTimeInterval: 0.01)
        store.update(id: id, tags: ["x", "y"])

        let updated = try XCTUnwrap(store.all().first)
        XCTAssertEqual(updated.text, "Text", "text left unchanged when nil is passed")
        XCTAssertEqual(updated.tags, ["x", "y"])
        XCTAssertEqual(updated.createdAt, originalCreatedAt, "createdAt is never touched by update")
        XCTAssertGreaterThan(updated.updatedAt, originalUpdatedAt)
    }

    func testUpdateOnUnknownIDIsANoOp() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)
        store.add(text: "Known", tags: [], source: "user")

        store.update(id: UUID(), text: "Should not appear anywhere")

        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.text, "Known")
    }

    // MARK: - 3. digest

    func testDigestReflectsCurrentMemories() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)

        XCTAssertEqual(store.digest(), "", "no memories yet")

        store.add(text: "Primary goal: Hypertrophy", tags: ["goal"])
        let digest = store.digest()
        XCTAssertTrue(digest.contains("Coach memory"))
        XCTAssertTrue(digest.contains("Primary goal: Hypertrophy"))
        XCTAssertTrue(digest.contains("[tags: goal]"))
    }

    func testDigestIsBoundedByLimit() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)

        for i in 0..<40 {
            store.add(text: "Memory number \(i)")
        }

        let digest = store.digest(limit: 5, maxChars: 100_000)
        // One header line + exactly `limit` memory lines.
        let lines = digest.split(separator: "\n")
        XCTAssertEqual(lines.count, 1 + 5)
    }

    func testDigestIsTruncatedToMaxChars() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)
        for i in 0..<50 {
            store.add(text: "A reasonably long memory line describing fact number \(i) in some detail.")
        }

        let digest = store.digest(limit: 50, maxChars: 200)
        XCTAssertLessThanOrEqual(digest.count, 200)
    }

    func testDigestChangesAfterAddAndRemove_provesContextRefresh() throws {
        let context = try makeContext()
        let store = MemoryStore(context: context)

        let before = store.digest()
        XCTAssertEqual(before, "")

        let id = store.add(text: "Fresh fact just added", tags: ["note"])
        let afterAdd = store.digest()
        XCTAssertNotEqual(before, afterAdd)
        XCTAssertTrue(afterAdd.contains("Fresh fact just added"))

        store.remove(id: id)
        let afterRemove = store.digest()
        XCTAssertEqual(afterRemove, "", "digest reflects the store's live state, not a stale cache")
    }
}
