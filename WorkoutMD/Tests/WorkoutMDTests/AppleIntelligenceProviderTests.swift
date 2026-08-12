import FoundationModels
import XCTest
@testable import WorkoutMD

final class AppleIntelligenceProviderTests: XCTestCase {
    func testAvailabilityMapsEveryFoundationModelsReason() {
        XCTAssertEqual(
            AppleIntelligenceCoachProvider.availability(for: .available),
            .available
        )
        XCTAssertEqual(
            AppleIntelligenceCoachProvider.availability(for: .unavailable(.deviceNotEligible)),
            .deviceNotEligible
        )
        XCTAssertEqual(
            AppleIntelligenceCoachProvider.availability(for: .unavailable(.appleIntelligenceNotEnabled)),
            .notEnabled
        )
        XCTAssertEqual(
            AppleIntelligenceCoachProvider.availability(for: .unavailable(.modelNotReady)),
            .modelNotReady
        )
    }

    func testAppleIntelligenceIsKeylessAndDoesNotBuildAHostedProviderConfig() {
        let defaults = UserDefaults(suiteName: "AppleIntelligenceProviderTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.providerKind = .appleIntelligence

        XCTAssertFalse(settings.providerKind.supportsBYOK)
        XCTAssertFalse(settings.providerKind.usesModelPicker)
        XCTAssertNil(settings.providerConfig(apiKey: "must-not-be-used"))
        XCTAssertNil(try CoachSecrets.apiKey(for: .appleIntelligence))
    }

    func testPersistedHistoryIsRehydratedIntoTheNativePrompt() {
        let history = #"[{"role":"user","content":"My elbow is sore"},{"role":"assistant","content":"Keep it submaximal."}]"#

        let prompt = AppleIntelligenceCoachProvider.prompt(
            userMessage: "Athlete note: Adjust today.",
            historyJSON: history
        )

        XCTAssertTrue(prompt.contains("Athlete: My elbow is sore"))
        XCTAssertTrue(prompt.contains("Coach: Keep it submaximal."))
        XCTAssertTrue(prompt.hasSuffix("Athlete note: Adjust today."))
    }

    func testNativePromptStaysInsideCompactOnDeviceBudgetAndKeepsTheAthleteNote() {
        let oversizedContext = "MEMORY " + String(repeating: "m", count: 8_000)
            + "\n\nAthlete note: Keep the session easy today."

        let prompt = AppleIntelligenceCoachProvider.prompt(
            userMessage: oversizedContext,
            historyJSON: "[]"
        )

        XCTAssertLessThanOrEqual(prompt.count, 2_500)
        XCTAssertTrue(prompt.hasPrefix("MEMORY"))
        XCTAssertTrue(prompt.hasSuffix("Athlete note: Keep the session easy today."))
        XCTAssertTrue(prompt.contains("context trimmed for on-device model"))
    }

    func testToolArgumentsAcceptCompactOrFencedJSONObjectAndRejectAnythingElse() throws {
        let compact = #"{"operations":[{"op":"updateSet","seconds":7,"targetMinKg":30,"targetMaxKg":34}]}"#
        let fenced = "```json\n\(compact)\n```"

        let normalized = try XCTUnwrap(AppleIntelligenceCoachProvider.normalizedToolArguments(compact))
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: Data(normalized.utf8)) as? NSDictionary,
            try JSONSerialization.jsonObject(with: Data(compact.utf8)) as? NSDictionary
        )
        XCTAssertNotNil(AppleIntelligenceCoachProvider.normalizedToolArguments(fenced))
        XCTAssertNil(AppleIntelligenceCoachProvider.normalizedToolArguments("not json"))
        XCTAssertNil(AppleIntelligenceCoachProvider.normalizedToolArguments("[1,2,3]"))
    }
}
