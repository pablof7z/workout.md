import Foundation
import XCTest
@testable import WorkoutMD

@MainActor
final class BYOKProviderConnectorTests: XCTestCase {
    func testAuthorizationRequestsOnlyTheSelectedProviderWithPKCE() throws {
        let url = BYOKProviderConnector.authorizationURL(
            providers: [.openRouter],
            verifier: "a-verifier-that-is-long-enough-for-this-contract-test",
            state: "expected-state"
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [])

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "byok.f7z.io")
        XCTAssertEqual(components.path, "/authorize")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["client_id"], "com.workoutmd.prototype")
        XCTAssertEqual(query["redirect_uri"], "workoutmd://byok")
        XCTAssertEqual(query["scope"], "key:openrouter")
        XCTAssertEqual(query["state"], "expected-state")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertFalse(try XCTUnwrap(query["code_challenge"]).isEmpty)
    }

    func testCallbackRequiresExactOriginAndState() throws {
        let valid = try XCTUnwrap(URL(string: "workoutmd://byok?code=grant-code&state=expected"))
        XCTAssertEqual(
            try BYOKProviderConnector.authorizationCode(from: valid, expectedState: "expected"),
            "grant-code"
        )

        let wrongHost = try XCTUnwrap(URL(string: "workoutmd://attacker?code=grant-code&state=expected"))
        XCTAssertThrowsError(
            try BYOKProviderConnector.authorizationCode(from: wrongHost, expectedState: "expected")
        )

        let wrongState = try XCTUnwrap(URL(string: "workoutmd://byok?code=grant-code&state=wrong"))
        XCTAssertThrowsError(
            try BYOKProviderConnector.authorizationCode(from: wrongState, expectedState: "expected")
        )
    }

    func testCallbackRejectsDenialWithoutValidState() throws {
        let validDenial = try XCTUnwrap(URL(string: "workoutmd://byok?error=access_denied&state=expected"))
        XCTAssertThrowsError(
            try BYOKProviderConnector.authorizationCode(from: validDenial, expectedState: "expected")
        )

        let forgedDenial = try XCTUnwrap(URL(string: "workoutmd://byok?error=access_denied&state=wrong"))
        XCTAssertThrowsError(
            try BYOKProviderConnector.authorizationCode(from: forgedDenial, expectedState: "expected")
        )
    }

    func testCallbackRejectsMissingAndAmbiguousParameters() throws {
        let missingCode = try XCTUnwrap(URL(string: "workoutmd://byok?state=expected"))
        XCTAssertThrowsError(
            try BYOKProviderConnector.authorizationCode(from: missingCode, expectedState: "expected")
        )

        let duplicateState = try XCTUnwrap(
            URL(string: "workoutmd://byok?code=grant-code&state=expected&state=other")
        )
        XCTAssertThrowsError(
            try BYOKProviderConnector.authorizationCode(from: duplicateState, expectedState: "expected")
        )

        let duplicateCode = try XCTUnwrap(
            URL(string: "workoutmd://byok?code=first&code=second&state=expected")
        )
        XCTAssertThrowsError(
            try BYOKProviderConnector.authorizationCode(from: duplicateCode, expectedState: "expected")
        )
    }

    func testDecodesSingleAndMultiProviderTokenResponses() throws {
        let singleJSON = """
        {"token_type":"raw_api_key","provider":"openrouter","api_key":"secret-value",\
        "key_id":"key-1","key_label":"Default"}
        """
        let single = try JSONDecoder().decode(BYOKTokenResponse.self, from: Data(singleJSON.utf8))
        let singleGrants = try single.grants(expectedProviders: ["openrouter"])
        XCTAssertEqual(singleGrants.count, 1)
        XCTAssertEqual(singleGrants[0].provider, .openRouter)
        XCTAssertEqual(singleGrants[0].keyID, "key-1")

        let multiJSON = """
        {"token_type":"raw_api_keys","providers":[\
        {"provider":"openrouter","api_key":"first-secret","key_id":"key-1","key_label":"Primary"},\
        {"provider":"ollama","api_key":"second-secret","key_id":"key-2","key_label":"Cloud"}]}
        """
        let multi = try JSONDecoder().decode(BYOKTokenResponse.self, from: Data(multiJSON.utf8))
        let multiGrants = try multi.grants(expectedProviders: ["openrouter", "ollama"])
        XCTAssertEqual(multiGrants.map(\.provider), [.openRouter, .ollama])
        XCTAssertEqual(multiGrants.map(\.keyLabel), ["Primary", "Cloud"])
    }

    func testAllowsAUserToSkipOneRequestedProvider() throws {
        let json = #"{"providers":[{"provider":"openrouter","api_key":"secret-value"}]}"#
        let response = try JSONDecoder().decode(BYOKTokenResponse.self, from: Data(json.utf8))
        let grants = try response.grants(expectedProviders: ["openrouter", "ollama"])

        XCTAssertEqual(grants.map(\.provider), [.openRouter])
    }

    func testRejectsUnrequestedOrEmptyProviderKeys() throws {
        let unexpectedJSON = #"{"provider":"ollama","api_key":"secret-value"}"#
        let unexpected = try JSONDecoder().decode(BYOKTokenResponse.self, from: Data(unexpectedJSON.utf8))
        XCTAssertThrowsError(
            try unexpected.grants(expectedProviders: ["openrouter"])
        )

        let emptyJSON = #"{"provider":"openrouter","api_key":""}"#
        let empty = try JSONDecoder().decode(BYOKTokenResponse.self, from: Data(emptyJSON.utf8))
        XCTAssertThrowsError(
            try empty.grants(expectedProviders: ["openrouter"])
        )
    }
}
