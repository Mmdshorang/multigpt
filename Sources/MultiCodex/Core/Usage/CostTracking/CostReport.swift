import Foundation

struct CostReport: Equatable {
    let accountName: String
    let totalCostUSD: Double
    let todayCostUSD: Double
    let weekCostUSD: Double
    let byModel: [String: Double]
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let sampledAt: Date

    var formattedTotal: String { CostFormatter.usd(totalCostUSD) }
    var formattedToday: String { CostFormatter.usd(todayCostUSD) }
    var formattedWeek: String { CostFormatter.usd(weekCostUSD) }

    static let zero = CostReport(
        accountName: "",
        totalCostUSD: 0,
        todayCostUSD: 0,
        weekCostUSD: 0,
        byModel: [:],
        totalInputTokens: 0,
        totalOutputTokens: 0,
        sampledAt: Date()
    )
}

enum CostFormatter {
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    static func tokens(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 { return String(format: "%.1fM", Double(absValue) / 1_000_000) }
        if absValue >= 1_000 { return String(format: "%.1fK", Double(absValue) / 1_000) }
        return "\(value)"
    }
}
