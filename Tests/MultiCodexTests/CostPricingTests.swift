import XCTest
@testable import MultiCodex

final class CostPricingTests: XCTestCase {
    func testKnownModelCostCalculation() {
        let cost = CostPricing.costUSD(
            model: "gpt-5-codex",
            inputTokens: 1000,
            cachedInputTokens: 500,
            outputTokens: 500
        )
        XCTAssertNotNil(cost)
        XCTAssertTrue(cost! > 0)
    }

    func testUnknownModelReturnsNil() {
        XCTAssertNil(CostPricing.costUSD(model: "unknown-model", inputTokens: 1000, cachedInputTokens: 0, outputTokens: 500))
    }

    func testNormalizeModelStripsDateSuffix() {
        XCTAssertEqual(CostPricing.normalizeModel("gpt-5-codex-2025-06-01"), "gpt-5-codex")
    }

    func testNormalizeModelStripsProviderPrefix() {
        XCTAssertEqual(CostPricing.normalizeModel("openai/gpt-5"), "gpt-5")
    }

    func testNormalizeModelPassesThroughUnknown() {
        XCTAssertEqual(CostPricing.normalizeModel("claude-4"), "claude-4")
    }
}
