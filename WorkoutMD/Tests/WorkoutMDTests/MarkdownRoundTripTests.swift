import XCTest
import SwiftData
@testable import WorkoutMD

/// Tests the Markdown round trip added for domain-primitives.md §11: `plan.md`/`sessions/*.md` carry
/// a hidden, machine-canonical block (`CanonicalMarkdown`) alongside the pretty human body
/// `MarkdownGenerator` already rendered — `MarkdownParser` decodes it back to `PlanSnapshot`/
/// `SessionDTO`, and `CanonicalImporter` reconstructs SwiftData records from that, with a conflict
/// policy of "history is factual/append-only, plans are last-writer-wins-as-a-new-revision".
/// `@testable import WorkoutMD` for the same reason `PlanRepositoryTests` needs it — see that file's
/// header comment.
final class MarkdownRoundTripTests: XCTestCase {

    // MARK: - Fixture

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            WorkoutRecord.self,
            ExerciseRecord.self,
            SetRecord.self,
            CoachNoteRecord.self,
            HeartRateSampleRecord.self,
            PlanRecord.self,
            PlanBlockRecord.self,
            PlanExerciseRecord.self,
            PlanSetRecord.self,
            PlanSessionRecord.self,
            PlanRevisionRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    /// A whole-second `Date` — `CanonicalMarkdown`'s `.iso8601` JSON date strategy truncates to
    /// second precision, so a fixture date must already be whole-second for round-trip equality to
    /// hold (this mirrors real persisted dates closely enough; sub-second precision was never load-
    /// bearing for this app).
    private func fixtureDate(_ offsetSeconds: TimeInterval = 0) -> Date {
        Date(timeIntervalSince1970: 1_750_000_000 + offsetSeconds)
    }

    /// A multi-session `PlanSnapshot`: two sessions, one straight-sets block and one superset block,
    /// exercising every field `BlockSnapshot`/`ExerciseSnapshot`/`SetSnapshot` carry.
    private func makeMultiSessionSnapshot() -> PlanSnapshot {
        let session1ID = UUID(), session2ID = UUID()
        let straightBlockID = UUID(), supersetBlockID = UUID()
        let benchID = UUID(), rowID = UUID(), curlID = UUID()

        let straightBlock = BlockSnapshot(
            id: straightBlockID, kind: .straight, label: "Bench Press", rounds: 1, restSeconds: nil,
            exercises: [
                ExerciseSnapshot(
                    id: benchID, name: "Bench Press", cue: "Elbows tucked",
                    sets: [
                        SetSnapshot(id: UUID(), reps: 8, weight: 135, seconds: nil),
                        SetSnapshot(id: UUID(), reps: 6, weight: 145, seconds: nil)
                    ])
            ])

        let supersetBlock = BlockSnapshot(
            id: supersetBlockID, kind: .superset, label: "Superset A", rounds: 3, restSeconds: 60,
            exercises: [
                ExerciseSnapshot(
                    id: rowID, name: "Row", cue: "Squeeze shoulder blades",
                    sets: [SetSnapshot(id: UUID(), reps: 10, weight: 80, seconds: nil)]),
                ExerciseSnapshot(
                    id: curlID, name: "Plank", cue: "Brace core",
                    sets: [SetSnapshot(id: UUID(), reps: nil, weight: nil, seconds: 45)])
            ])

        return PlanSnapshot(
            id: UUID(),
            name: "Upper/Lower",
            goal: "Hypertrophy",
            notes: "Deload every 5th week",
            sessions: [
                SessionSnapshot(id: session1ID, name: "Upper A", blocks: [straightBlock]),
                SessionSnapshot(id: session2ID, name: "Upper B", blocks: [supersetBlock])
            ],
            cursorSessionID: session2ID
        )
    }

    /// A `WorkoutRecord` with a straight-sets exercise (one clean set, one substituted+RPE'd set)
    /// plus a coach note — exercises prescribed/actual divergence, RPE, substitution, and notes.
    private func makeWorkoutRecord() -> WorkoutRecord {
        let record = WorkoutRecord(
            id: UUID(), date: fixtureDate(), name: "Tuesday Upper", goal: "Hypertrophy",
            totalSets: 2, loggedSets: 2, averageRPE: 8.0, isMock: false
        )
        let exercise = ExerciseRecord(
            id: UUID(), order: 0, name: "Bench Press", blockName: "Bench Press",
            groupKind: .straight, groupLabel: nil
        )
        let cleanSet = SetRecord(
            id: UUID(), order: 0, setNumber: 1, round: nil, totalRounds: nil,
            prescribedReps: 8, prescribedWeight: 135, prescribedSeconds: nil,
            actualReps: 8, actualWeight: 135, actualSeconds: nil,
            rpe: 7.5, skipped: false, substituted: false, substitutedName: nil,
            notes: nil, sourceStepID: UUID()
        )
        let substitutedSet = SetRecord(
            id: UUID(), order: 1, setNumber: 2, round: nil, totalRounds: nil,
            prescribedReps: 8, prescribedWeight: 135, prescribedSeconds: nil,
            actualReps: 12, actualWeight: 95, actualSeconds: nil,
            rpe: 8.5, skipped: false, substituted: true, substitutedName: "Machine Press",
            notes: "Shoulder felt tight", sourceStepID: UUID()
        )
        exercise.sets = [cleanSet, substitutedSet]
        record.exercises = [exercise]
        record.coachNotes = [
            CoachNoteRecord(
                id: UUID(), order: 0, kind: .coach, text: "Good work, watch that shoulder.",
                exerciseName: "Bench Press", date: fixtureDate(60), planID: UUID()
            )
        ]
        record.heartRateSensorName = "Polar H10 12345678"
        record.heartRateSamples = [
            HeartRateSampleRecord(id: UUID(), timestamp: fixtureDate(10), beatsPerMinute: 121),
            HeartRateSampleRecord(id: UUID(), timestamp: fixtureDate(11), beatsPerMinute: 149)
        ]
        return record
    }

    // MARK: - 1. Plan round trip

    func testPlanRoundTripPreservesSnapshotExactly() throws {
        let snapshot = makeMultiSessionSnapshot()
        let markdown = MarkdownGenerator.renderPlan(snapshot)

        // Pretty human body is still there.
        XCTAssertTrue(markdown.contains("# Upper/Lower"))
        XCTAssertTrue(markdown.contains("Bench Press"))
        XCTAssertTrue(markdown.contains("## Upper A"))
        XCTAssertTrue(markdown.contains("## Upper B"))

        // Canonical block is invisible — wrapped in an HTML comment.
        XCTAssertTrue(markdown.contains("<!-- workout.md:canonical v1"))
        XCTAssertTrue(markdown.contains("-->"))

        let parsed = MarkdownParser.parsePlan(markdown)
        XCTAssertEqual(parsed, snapshot)
    }

    // MARK: - 2. Session round trip

    func testSessionRoundTripPreservesEveryLoggedFact() throws {
        let record = makeWorkoutRecord()
        let originalDTO = SessionDTO.from(record)

        let markdown = MarkdownGenerator.renderSession(record)
        XCTAssertTrue(markdown.contains("# Tuesday Upper"))
        XCTAssertTrue(markdown.contains("<!-- workout.md:canonical v1"))

        guard let parsedDTO = MarkdownParser.parseSession(markdown) else {
            return XCTFail("Expected a decodable canonical session block")
        }
        XCTAssertEqual(parsedDTO, originalDTO)

        let reconstructed = parsedDTO.makeRecord()
        let reconstructedDTO = SessionDTO.from(reconstructed)
        XCTAssertEqual(reconstructedDTO, originalDTO)

        // Spot-check a few fields directly against the live objects too, not just DTO equality.
        XCTAssertEqual(reconstructed.id, record.id)
        let originalSets = record.exercises[0].sets.sorted { $0.order < $1.order }
        let reconstructedSets = reconstructed.exercises[0].sets.sorted { $0.order < $1.order }
        XCTAssertEqual(reconstructedSets[0].prescribedReps, originalSets[0].prescribedReps)
        XCTAssertEqual(reconstructedSets[0].actualReps, originalSets[0].actualReps)
        XCTAssertEqual(reconstructedSets[0].rpe, originalSets[0].rpe)
        XCTAssertEqual(reconstructedSets[1].substituted, true)
        XCTAssertEqual(reconstructedSets[1].substitutedName, "Machine Press")
        XCTAssertEqual(reconstructedSets[1].notes, "Shoulder felt tight")
        XCTAssertEqual(reconstructed.coachNotes.first?.text, "Good work, watch that shoulder.")
        XCTAssertEqual(reconstructed.heartRateSensorName, "Polar H10 12345678")
        XCTAssertEqual(reconstructed.heartRateSamples.map(\.beatsPerMinute).sorted(), [121, 149])
    }

    func testPrePolarCanonicalSessionStillDecodes() throws {
        let dto = SessionDTO.from(makeWorkoutRecord())
        let encoded = try CanonicalMarkdown.encoder.encode(dto)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "heartRateSensorName")
        object.removeValue(forKey: "heartRateSamples")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try CanonicalMarkdown.decoder.decode(SessionDTO.self, from: legacyData)

        XCTAssertNil(decoded.heartRateSensorName)
        XCTAssertNil(decoded.heartRateSamples)
    }

    // MARK: - 3. Importer conflict policy

    func testImportSessionTwiceIsAppendOnlyAndPreservesOriginalFacts() throws {
        let context = try makeContext()
        let importer = CanonicalImporter(context: context)

        let record = makeWorkoutRecord()
        var dto = SessionDTO.from(record)

        let firstOutcome = importer.importSession(dto)
        XCTAssertEqual(firstOutcome, .inserted(dto.id))

        // Mutate the DTO's actuals as if a hand-edited external file changed the "same" session id,
        // then import again — history is factual/append-only, so this must be a no-op.
        dto.exercises[0].sets[0].actualReps = 999
        dto.exercises[0].sets[0].rpe = 1.0
        dto.exercises[0].sets[1].notes = "This should never land"

        let secondOutcome = importer.importSession(dto)
        XCTAssertEqual(secondOutcome, .skippedExisting(dto.id))

        var descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.id == dto.id })
        descriptor.fetchLimit = 1
        let stored = try XCTUnwrap(try context.fetch(descriptor).first)
        let storedSets = stored.exercises[0].sets.sorted { $0.order < $1.order }
        XCTAssertEqual(storedSets[0].actualReps, 8, "the original logged fact must survive")
        XCTAssertEqual(storedSets[0].rpe, 7.5, "the original RPE must survive")
        XCTAssertEqual(storedSets[1].notes, "Shoulder felt tight", "the original note must survive")
    }

    func testImportPlanForExistingChangedPlanCreatesNewRevisionNotSilentOverwrite() throws {
        let context = try makeContext()
        let importer = CanonicalImporter(context: context)

        let snapshot = makeMultiSessionSnapshot()
        let createdOutcome = importer.importPlan(snapshot)
        XCTAssertEqual(createdOutcome, .created(snapshot.id))

        var revisionsDescriptor = FetchDescriptor<PlanRevisionRecord>(
            predicate: #Predicate { $0.planID == snapshot.id })
        let revisionsAfterCreate = try context.fetch(revisionsDescriptor)
        XCTAssertEqual(revisionsAfterCreate.count, 1)

        // Import the "same" plan id again with unchanged content: no-op, no new revision.
        let unchangedOutcome = importer.importPlan(snapshot)
        XCTAssertEqual(unchangedOutcome, .unchanged(snapshot.id))
        XCTAssertEqual(try context.fetch(revisionsDescriptor).count, 1)

        // Now import a changed snapshot under the same id — must land as a NEW revision, and the
        // plan's stored graph must reconcile to the new content (last-writer-wins), never silently
        // discarded.
        var changed = snapshot
        changed.name = "Upper/Lower (edited externally)"
        let revisedOutcome = importer.importPlan(changed)
        guard case .revised(let revisedPlanID, let revisionID) = revisedOutcome else {
            return XCTFail("Expected .revised, got \(revisedOutcome)")
        }
        XCTAssertEqual(revisedPlanID, snapshot.id)

        revisionsDescriptor = FetchDescriptor<PlanRevisionRecord>(
            predicate: #Predicate { $0.planID == snapshot.id })
        let revisionsAfterEdit = try context.fetch(revisionsDescriptor)
        XCTAssertEqual(revisionsAfterEdit.count, 2)
        XCTAssertTrue(revisionsAfterEdit.contains { $0.id == revisionID })

        var planDescriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.id == snapshot.id })
        planDescriptor.fetchLimit = 1
        let storedPlan = try XCTUnwrap(try context.fetch(planDescriptor).first)
        XCTAssertEqual(storedPlan.name, "Upper/Lower (edited externally)")
    }

    // MARK: - 4. README / no-canonical-block Markdown

    private let readmeMarkdown = """
    # Workout.md Log

    Private, app-managed log of workout sessions. Each file under `sessions/` is a Markdown \
    snapshot of one workday's session. This file is a running index, kept up to date by the app.

    ## Sessions

    - [sessions/2026-07-08-tuesday-upper.md](sessions/2026-07-08-tuesday-upper.md)
    """

    func testParsePlanAndParseSessionReturnNilForReadmeStyleMarkdown() {
        XCTAssertNil(MarkdownParser.parsePlan(readmeMarkdown))
        XCTAssertNil(MarkdownParser.parseSession(readmeMarkdown))
        XCTAssertNil(MarkdownParser.canonicalJSON(in: readmeMarkdown))
    }

    func testRestoreFromSyncSkipsReadmeAndNoCanonicalFilesWithoutCrashing() throws {
        let context = try makeContext()
        let importer = CanonicalImporter(context: context)

        let handWritten = "# Leg Day\n\nJust some notes, no canonical block here.\n"

        let summary = importer.restoreFromSync(files: [
            (path: "README.md", content: readmeMarkdown),
            (path: "sessions/hand-written.md", content: handWritten)
        ])

        XCTAssertEqual(summary.plansImported, 0)
        XCTAssertEqual(summary.sessionsImported, 0)
        // README.md is skipped outright (not even counted as "no canonical block" — it's never
        // expected to have one); the hand-written session file IS counted, since it's a path that
        // was supposed to carry a canonical block but didn't.
        XCTAssertEqual(summary.skippedNoCanonicalBlock, 1)
    }

    func testRestoreFromSyncImportsRealCanonicalFiles() throws {
        let context = try makeContext()
        let importer = CanonicalImporter(context: context)

        let snapshot = makeMultiSessionSnapshot()
        let record = makeWorkoutRecord()
        let planMarkdown = MarkdownGenerator.renderPlan(snapshot)
        let sessionMarkdown = MarkdownGenerator.renderSession(record)

        let summary = importer.restoreFromSync(files: [
            (path: "README.md", content: readmeMarkdown),
            (path: "plan.md", content: planMarkdown),
            (path: "sessions/2026-07-08-tuesday-upper.md", content: sessionMarkdown)
        ])

        XCTAssertEqual(summary.plansImported, 1)
        XCTAssertEqual(summary.sessionsImported, 1)
        XCTAssertEqual(summary.skippedNoCanonicalBlock, 0)

        var planDescriptor = FetchDescriptor<PlanRecord>(predicate: #Predicate { $0.id == snapshot.id })
        planDescriptor.fetchLimit = 1
        XCTAssertNotNil(try context.fetch(planDescriptor).first)

        let recordID = record.id
        var workoutDescriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.id == recordID })
        workoutDescriptor.fetchLimit = 1
        XCTAssertNotNil(try context.fetch(workoutDescriptor).first)
    }
}
