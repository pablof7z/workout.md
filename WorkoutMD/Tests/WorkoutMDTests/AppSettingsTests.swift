import XCTest
@testable import WorkoutMD

/// Unit tests for `AppSettings`'s two-tier (`CoachModelTier.fast`/`.reasoning`) model selection —
/// the replacement for the old three `CoachModelRole`s. Each test builds an isolated `AppSettings`
/// backed by its own throwaway `UserDefaults` suite, so tests never read/write the app's real
/// defaults or interfere with each other.
final class AppSettingsTests: XCTestCase {

    private func makeSettings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "AppSettingsTests-\(UUID().uuidString)")!
        return AppSettings(defaults: defaults)
    }

    // MARK: - model(for:) fallback

    func testReasoningTierFallsBackToFastModelWhenUnset() {
        let settings = makeSettings()
        settings.fastModel = "anthropic/claude-3-haiku"

        XCTAssertTrue(settings.reasoningModel.isEmpty, "reasoningModel itself stays empty — only model(for:) falls back")
        XCTAssertEqual(settings.model(for: .reasoning), "anthropic/claude-3-haiku")
        XCTAssertEqual(settings.model(for: .fast), "anthropic/claude-3-haiku")
    }

    func testReasoningTierUsesItsOwnModelOnceSet() {
        let settings = makeSettings()
        settings.fastModel = "anthropic/claude-3-haiku"
        settings.reasoningModel = "anthropic/claude-3-opus"

        XCTAssertEqual(settings.model(for: .reasoning), "anthropic/claude-3-opus")
        XCTAssertEqual(settings.model(for: .fast), "anthropic/claude-3-haiku", "fast tier is unaffected by reasoning")
    }

    func testBothTiersAreEmptyByDefaultWithNoHardcodedModel() {
        let settings = makeSettings()

        XCTAssertEqual(settings.fastModel, "")
        XCTAssertEqual(settings.model(for: .fast), "")
        XCTAssertEqual(settings.model(for: .reasoning), "", "falls back to the equally-empty fast model")
    }

    // MARK: - setModel(_:for:) round trip

    func testSetModelRoundTripsPerTierIndependently() {
        let settings = makeSettings()

        settings.setModel("openrouter/model-a", for: .fast)
        settings.setModel("openrouter/model-b", for: .reasoning)

        XCTAssertEqual(settings.fastModel, "openrouter/model-a")
        XCTAssertEqual(settings.reasoningModel, "openrouter/model-b")
        XCTAssertEqual(settings.model(for: .fast), "openrouter/model-a")
        XCTAssertEqual(settings.model(for: .reasoning), "openrouter/model-b")
    }

    func testSetModelForFastTierDoesNotTouchReasoningModel() {
        let settings = makeSettings()
        settings.setModel("openrouter/model-b", for: .reasoning)

        settings.setModel("openrouter/model-a", for: .fast)

        XCTAssertEqual(settings.reasoningModel, "openrouter/model-b", "unaffected by a fast-tier change")
    }
}
