import XCTest

/// Unit tests for `ThinkStripper` (see `WorkoutMD/Sources/Coach/ThinkStripper.swift`), compiled
/// directly into this logic-only test target (no host app / `@testable import` — see `project.yml`)
/// so they exercise exactly the pure helper `CoachStreamSink` uses, one raw delta at a time, the way
/// the real streaming coach path does.
final class ThinkStripperTests: XCTestCase {

    // MARK: - Non-streaming (single `strip(_:)` call)

    func testPlainTextWithNoThinkTagsPassesThroughUnchanged() {
        let text = "Sets 1 and 2 dropped to RPE 7. Bump to 135 next time."
        XCTAssertEqual(ThinkStripper.strip(text), text)
    }

    func testEmptyStringPassesThrough() {
        XCTAssertEqual(ThinkStripper.strip(""), "")
    }

    func testNormalThinkBlockIsRemoved() {
        let text = "Before. <think>reasoning about weights and fatigue</think> After."
        XCTAssertEqual(ThinkStripper.strip(text), "Before.  After.")
    }

    func testThinkingSpellingIsAlsoRemoved() {
        let text = "Before.<thinking>let me reason</thinking>After."
        XCTAssertEqual(ThinkStripper.strip(text), "Before.After.")
    }

    func testMismatchedOpenCloseSpellingsStillToggle() {
        // Some models open with <think> and close with </thinking> (or vice versa) — either tag name
        // should toggle the same hidden state.
        let text = "Before.<think>reasoning</thinking>After."
        XCTAssertEqual(ThinkStripper.strip(text), "Before.After.")
    }

    func testCaseInsensitiveTags() {
        let text = "Before.<THINK>reasoning</THINK>After."
        XCTAssertEqual(ThinkStripper.strip(text), "Before.After.")
    }

    func testUnterminatedTrailingThinkBlockHidesRestOfBuffer() {
        let text = "Here's my plan. <think>still reasoning, no close yet"
        XCTAssertEqual(ThinkStripper.strip(text), "Here's my plan. ")
    }

    func testOrphanCloseWithNoPrecedingContentIsJustStripped() {
        let text = "</think>Sets 1 and 2 dropped."
        XCTAssertEqual(ThinkStripper.strip(text), "Sets 1 and 2 dropped.")
    }

    func testOrphanCloseHidesUnmarkedLeadingReasoning() {
        // The exact shape of the reported bug: no opening tag at all, reasoning prose runs right up
        // to a bare </think>, then the real answer follows.
        let text = "Let me summarize this for the athlete.</think>Sets 1 and 2 dropped to RPE 7."
        XCTAssertEqual(ThinkStripper.strip(text), "Sets 1 and 2 dropped to RPE 7.")
    }

    func testStrayCloseAfterARealBlockIsJustStrippedNotRetroactive() {
        // Once a real <think>...</think> pair has already resolved, a later bare </think> is just a
        // stray marker — it must not wipe out the real answer that already displayed.
        let text = "<think>reasoning</think>Sets 1 and 2 dropped.</think> Nice work."
        XCTAssertEqual(ThinkStripper.strip(text), "Sets 1 and 2 dropped. Nice work.")
    }

    func testMultipleThinkBlocks() {
        let text = "A<think>one</think>B<think>two</think>C"
        XCTAssertEqual(ThinkStripper.strip(text), "ABC")
    }

    // MARK: - Streaming (chunked deltas via `Buffer`)

    func testStreamingNormalBlockSplitAcrossManyDeltas() {
        var buffer = ThinkStripper.Buffer()
        let deltas = [
            "Sure, here's the plan. ",
            "<thi", "nk>", "let me reason about ", "weights and fatigue", "</th", "ink>",
            " Do 3 sets of 8 at 135.",
        ]
        // Splitting a tag itself across deltas ("<thi" + "nk>") is a real streaming shape (arbitrary
        // token boundaries), and must still resolve once the full tag has arrived.
        var lastVisible = ""
        for delta in deltas {
            lastVisible = buffer.append(delta)
        }
        XCTAssertEqual(lastVisible, "Sure, here's the plan.  Do 3 sets of 8 at 135.")
        XCTAssertEqual(buffer.visible, lastVisible)
    }

    func testStreamingNeverLeaksATagFragmentSplitAtADeltaBoundary() {
        var buffer = ThinkStripper.Buffer()
        // "<thi" alone isn't a complete tag yet — must be held back, not shown as literal text.
        XCTAssertEqual(buffer.append("Sure, here's the plan. "), "Sure, here's the plan. ")
        XCTAssertEqual(buffer.append("<thi"), "Sure, here's the plan. ")
        XCTAssertEqual(buffer.append("nk>reasoning</think>"), "Sure, here's the plan. ")
        XCTAssertEqual(buffer.append(" Done."), "Sure, here's the plan.  Done.")
    }

    func testStreamingHoldsBackAmbiguousLeadingAngleBracketInPlainText() {
        // A lone "<" at a delta boundary is ambiguous (could be the start of a tag) and should be
        // held back for one step even with no think tags involved at all, then released once the
        // following characters rule out a tag.
        var buffer = ThinkStripper.Buffer()
        XCTAssertEqual(buffer.append("Reps <"), "Reps ")
        XCTAssertEqual(buffer.append(" 5 count as a fail."), "Reps < 5 count as a fail.")
    }

    func testStreamingHidesContentWhileThinkBlockIsOpen() {
        var buffer = ThinkStripper.Buffer()

        XCTAssertEqual(buffer.append("Here's my plan. "), "Here's my plan. ")
        XCTAssertEqual(buffer.append("<think>"), "Here's my plan. ")
        XCTAssertEqual(buffer.append("weighing options here"), "Here's my plan. ")
        XCTAssertEqual(buffer.append(" more reasoning"), "Here's my plan. ")
        // Still nothing new revealed until the close tag arrives.
        XCTAssertEqual(buffer.append("</think>"), "Here's my plan. ")
        XCTAssertEqual(buffer.append(" Do 3 sets of 8."), "Here's my plan.  Do 3 sets of 8.")
    }

    func testStreamingOrphanCloseRetroactivelyHidesLeadingDeltas() {
        var buffer = ThinkStripper.Buffer()

        // No opening tag ever arrives — the model just starts reasoning. Each of these deltas is
        // provisionally "visible" (there's no way yet to know a </think> is coming)...
        XCTAssertEqual(buffer.append("Let me "), "Let me ")
        XCTAssertEqual(buffer.append("summarize this "), "Let me summarize this ")
        XCTAssertEqual(buffer.append("for the athlete."), "Let me summarize this for the athlete.")

        // ...until the orphan close tag lands, at which point everything before it is retroactively
        // discarded and only the remainder (the real answer) is visible.
        XCTAssertEqual(buffer.append("</think>"), "")
        XCTAssertEqual(buffer.append("Sets 1 and 2 dropped."), "Sets 1 and 2 dropped.")
    }

    func testStreamingPlainTextNeverTouchedByStripper() {
        var buffer = ThinkStripper.Buffer()
        let deltas = ["No ", "reasoning ", "tags ", "here ", "at ", "all."]
        var accumulated = ""
        for delta in deltas {
            accumulated += delta
            XCTAssertEqual(buffer.append(delta), accumulated)
        }
        XCTAssertEqual(buffer.visible, "No reasoning tags here at all.")
    }

    func testStreamingOrphanCloseAsFirstDeltaAloneThenContent() {
        // A minimal, single-delta version of the orphan-close case (no leading reasoning at all).
        var buffer = ThinkStripper.Buffer()
        XCTAssertEqual(buffer.append("</think>"), "")
        XCTAssertEqual(buffer.append("Sets 1 and 2 dropped."), "Sets 1 and 2 dropped.")
    }
}
