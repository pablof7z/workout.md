import Foundation
import XCTest
@testable import WorkoutMD

/// Pure decode/mapping tests for the ported, capability/date-free OpenRouter model catalog (see
/// `WorkoutMD/Sources/Settings/ModelPicker/OpenRouterModelCatalog.swift`). Feeds a small hardcoded
/// `/models` JSON sample straight into `ModelCatalogService.decode(openRouterJSON:)` — the same
/// decode + `ModelCatalogOption` mapping `fetchModels(source: .openRouter)` uses — with no network
/// involved.
final class OpenRouterModelCatalogTests: XCTestCase {
    private let sampleJSON = """
    {
      "data": [
        {
          "id": "anthropic/claude-3.5-sonnet",
          "name": "Anthropic: Claude 3.5 Sonnet",
          "description": "A capable, balanced model.",
          "context_length": 200000,
          "pricing": {
            "prompt": "0.000003",
            "completion": "0.000015",
            "input_cache_read": "0.0000003"
          },
          "top_provider": {
            "context_length": 200000,
            "max_completion_tokens": 8192
          }
        },
        {
          "id": "google/gemini-2.0-flash-exp:free",
          "name": "Google: Gemini 2.0 Flash Experimental (free)",
          "context_length": 1000000,
          "pricing": {
            "prompt": "0",
            "completion": "0"
          },
          "top_provider": {
            "context_length": 1000000
          }
        },
        {
          "id": "openai/gpt-4o-mini",
          "name": "OpenAI: GPT-4o-mini",
          "context_length": 128000,
          "pricing": {
            "prompt": "0.00000015",
            "completion": "0.0000006"
          },
          "top_provider": {
            "context_length": 128000,
            "max_completion_tokens": 16384
          }
        }
      ]
    }
    """

    private func decode() throws -> [ModelCatalogOption] {
        try ModelCatalogService.decode(openRouterJSON: Data(sampleJSON.utf8))
    }

    func testProviderIDIsParsedFromBeforeTheFirstSlash() throws {
        let models = try decode()
        let claude = try XCTUnwrap(models.first { $0.id == "anthropic/claude-3.5-sonnet" })
        XCTAssertEqual(claude.providerID, "anthropic")

        let gemini = try XCTUnwrap(models.first { $0.id == "google/gemini-2.0-flash-exp:free" })
        XCTAssertEqual(gemini.providerID, "google")
    }

    func testPricingStringsAreConvertedToDollarsPerMillion() throws {
        let models = try decode()
        let claude = try XCTUnwrap(models.first { $0.id == "anthropic/claude-3.5-sonnet" })

        XCTAssertEqual(try XCTUnwrap(claude.promptCostPerMillion), 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(claude.completionCostPerMillion), 15.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(claude.cacheReadCostPerMillion), 0.3, accuracy: 0.0001)

        let gptMini = try XCTUnwrap(models.first { $0.id == "openai/gpt-4o-mini" })
        XCTAssertEqual(try XCTUnwrap(gptMini.promptCostPerMillion), 0.15, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(gptMini.completionCostPerMillion), 0.6, accuracy: 0.0001)
    }

    func testIsFreeReflectsZeroPricing() throws {
        let models = try decode()
        let gemini = try XCTUnwrap(models.first { $0.id == "google/gemini-2.0-flash-exp:free" })
        XCTAssertTrue(gemini.isFree)

        let claude = try XCTUnwrap(models.first { $0.id == "anthropic/claude-3.5-sonnet" })
        XCTAssertFalse(claude.isFree)
    }

    func testSearchTextContainsIDAndMaker() throws {
        let models = try decode()
        let claude = try XCTUnwrap(models.first { $0.id == "anthropic/claude-3.5-sonnet" })

        XCTAssertTrue(claude.searchText.contains("anthropic/claude-3.5-sonnet"))
        XCTAssertTrue(claude.searchText.contains("anthropic"))
        XCTAssertTrue(claude.searchText.contains("claude"))
    }

    func testLogoURLIsBuiltFromProviderID() throws {
        let models = try decode()
        let claude = try XCTUnwrap(models.first { $0.id == "anthropic/claude-3.5-sonnet" })
        XCTAssertEqual(claude.logoURL, URL(string: "https://models.dev/logos/anthropic.svg"))
    }

    func testContextAndOutputLimitsAreDecoded() throws {
        let models = try decode()
        let gptMini = try XCTUnwrap(models.first { $0.id == "openai/gpt-4o-mini" })
        XCTAssertEqual(gptMini.contextLength, 128000)
        XCTAssertEqual(gptMini.outputLimit, 16384)
    }

    func testDecodingWithoutModelsDevEnrichmentStillWorks() throws {
        // No modelsDevJSON passed — the catalog must stand on its own from OpenRouter data alone.
        let models = try decode()
        XCTAssertEqual(models.count, 3)
    }
}
