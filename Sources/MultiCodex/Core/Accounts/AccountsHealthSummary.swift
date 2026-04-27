import Foundation

/// Aggregate health summary across all accounts.
struct AccountsHealthSummary {
    let totalAccounts: Int
    let healthyAccounts: Int
    let atRiskAccounts: Int
    let aggregateFiveHourRemaining: Double
    let aggregateWeeklyRemaining: Double
    let nextResetAt: Date?

    static func from(_ accounts: [AccountUsage]) -> AccountsHealthSummary {
        let healthy = accounts.filter { $0.connectionState == .connected }
        let atRisk = healthy.filter { account in
            let fiveHour = account.usage.fiveHour.usedPercent ?? 0
            let weekly = account.usage.weekly.usedPercent ?? 0
            return fiveHour >= 80 || weekly >= 80
        }

        let avgFiveHour = healthy.isEmpty
            ? 0
            : healthy.reduce(0.0) { $0 + (100 - ($1.usage.fiveHour.usedPercent ?? 0)) } / Double(healthy.count)
        let avgWeekly = healthy.isEmpty
            ? 0
            : healthy.reduce(0.0) { $0 + (100 - ($1.usage.weekly.usedPercent ?? 0)) } / Double(healthy.count)

        let nextReset = healthy.flatMap { account in
            [account.usage.fiveHour.resetsAt, account.usage.weekly.resetsAt]
        }.compactMap { $0 }.min()

        return AccountsHealthSummary(
            totalAccounts: accounts.count,
            healthyAccounts: healthy.count,
            atRiskAccounts: atRisk.count,
            aggregateFiveHourRemaining: avgFiveHour,
            aggregateWeeklyRemaining: avgWeekly,
            nextResetAt: nextReset
        )
    }

    var summaryText: String {
        "\(healthyAccounts)/\(totalAccounts) healthy"
    }

    var detailText: String {
        var parts: [String] = []
        if atRiskAccounts > 0 {
            parts.append("\(atRiskAccounts) at risk")
        }
        parts.append(String(format: "5h: %.0f%% · Weekly: %.0f%%", aggregateFiveHourRemaining, aggregateWeeklyRemaining))
        return parts.joined(separator: " · ")
    }
}
