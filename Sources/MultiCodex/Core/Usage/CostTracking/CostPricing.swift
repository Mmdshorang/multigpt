import Foundation

/// Per-model token pricing for cost calculation.
enum CostPricing {
    struct ModelPricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheReadCostPerToken: Double
    }

    private static let models: [String: ModelPricing] = [
        "gpt-5": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
        "gpt-5-codex": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
        "gpt-5-mini": .init(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadCostPerToken: 2.5e-8),
        "gpt-5-nano": .init(inputCostPerToken: 5e-8, outputCostPerToken: 4e-7, cacheReadCostPerToken: 5e-9),
        "gpt-5-pro": .init(inputCostPerToken: 1.5e-5, outputCostPerToken: 1.2e-4, cacheReadCostPerToken: 1.5e-6),
        "gpt-5.1": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
        "gpt-5.1-codex": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
        "gpt-5.1-codex-max": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5, cacheReadCostPerToken: 1.25e-7),
        "gpt-5.1-codex-mini": .init(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6, cacheReadCostPerToken: 2.5e-8),
    ]

    static func normalizeModel(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("openai/") { name = String(name.dropFirst("openai/".count)) }
        if models[name] != nil { return name }
        if let range = name.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(name[..<range.lowerBound])
            if models[base] != nil { return base }
        }
        return name
    }

    static func costUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int
    ) -> Double? {
        let key = normalizeModel(model)
        guard let pricing = models[key] else { return nil }

        let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
        let nonCached = max(0, inputTokens - cached)

        return Double(nonCached) * pricing.inputCostPerToken
            + Double(cached) * pricing.cacheReadCostPerToken
            + Double(max(0, outputTokens)) * pricing.outputCostPerToken
    }
}
