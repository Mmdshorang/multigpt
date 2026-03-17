import Foundation

struct AccountSwitchRecommendation: Equatable {
    let accountName: String
    let reason: String
}

enum AccountSwitchRecommendationService {
    private static let failoverFiveHourLimitPercent = 95.0
    private static let failoverWeeklyLimitPercent = 98.0
    private static let expiryAwareMargin = 0.22
    private static let currentAccountStickyBonus = 0.18

    static func recommendation(
        for strategy: AccountSwitchingStrategy,
        accounts: [AccountUsage],
        now: Date = Date()
    ) -> AccountSwitchRecommendation? {
        guard accounts.count > 1 else {
            return nil
        }

        switch strategy {
        case .manual:
            return nil
        case .failover:
            return failoverRecommendation(accounts: accounts)
        case .expiryAware:
            return expiryAwareRecommendation(accounts: accounts, now: now)
        }
    }

    private static func failoverRecommendation(accounts: [AccountUsage]) -> AccountSwitchRecommendation? {
        let current = accounts.first(where: \.isCurrent)
        let candidates = eligibleAccounts(from: accounts, excluding: current?.name)
        guard let candidate = candidates.max(by: { fallbackScore(for: $0) < fallbackScore(for: $1) }) else {
            return nil
        }

        guard let current else {
            return AccountSwitchRecommendation(
                accountName: candidate.name,
                reason: "No current account is active, so MultiCodex picked the healthiest available one."
            )
        }

        if current.connectionState == .needsLogin {
            return AccountSwitchRecommendation(
                accountName: candidate.name,
                reason: "\(current.name) needs login, so MultiCodex moved to a healthy account."
            )
        }

        if current.connectionState == .error {
            return AccountSwitchRecommendation(
                accountName: candidate.name,
                reason: "\(current.name) could not refresh cleanly, so MultiCodex failed over."
            )
        }

        if isEffectivelyExhausted(current) {
            return AccountSwitchRecommendation(
                accountName: candidate.name,
                reason: "\(current.name) is at or near its limit, so MultiCodex failed over."
            )
        }

        return nil
    }

    private static func expiryAwareRecommendation(
        accounts: [AccountUsage],
        now: Date
    ) -> AccountSwitchRecommendation? {
        let current = accounts.first(where: \.isCurrent)
        let candidates = eligibleAccounts(from: accounts)
        guard !candidates.isEmpty else {
            return nil
        }

        let scored = candidates.map { account in
            (
                account: account,
                score: expiryAwareScore(
                    for: account,
                    now: now,
                    isCurrent: account.name == current?.name
                )
            )
        }

        guard let best = scored.max(by: { $0.score < $1.score }) else {
            return nil
        }

        guard let current else {
            return AccountSwitchRecommendation(
                accountName: best.account.name,
                reason: "MultiCodex picked the account that can use the most quota before the next reset."
            )
        }

        guard let currentScore = scored.first(where: { $0.account.name == current.name })?.score else {
            return AccountSwitchRecommendation(
                accountName: best.account.name,
                reason: "\(current.name) is not eligible for automatic use, so MultiCodex picked the best available account."
            )
        }

        guard best.account.name != current.name else {
            return nil
        }

        guard best.score > currentScore + expiryAwareMargin else {
            return nil
        }

        let reason = expiryAwareReason(candidate: best.account, current: current, now: now)
        return AccountSwitchRecommendation(accountName: best.account.name, reason: reason)
    }

    private static func eligibleAccounts(from accounts: [AccountUsage], excluding name: String? = nil) -> [AccountUsage] {
        accounts.filter { account in
            guard account.name != name else {
                return false
            }
            return account.hasAuth && account.connectionState == .connected
        }
    }

    private static func isEffectivelyExhausted(_ account: AccountUsage) -> Bool {
        let fiveHourUsed = account.usage.fiveHour.usedPercent ?? 0
        let weeklyUsed = account.usage.weekly.usedPercent ?? 0
        return fiveHourUsed >= failoverFiveHourLimitPercent || weeklyUsed >= failoverWeeklyLimitPercent
    }

    private static func fallbackScore(for account: AccountUsage) -> Double {
        let remainingFiveHour = remainingFraction(for: account.usage.fiveHour)
        let remainingWeekly = remainingFraction(for: account.usage.weekly)
        return (remainingFiveHour * 0.65) + (remainingWeekly * 0.35)
    }

    private static func expiryAwareScore(for account: AccountUsage, now: Date, isCurrent: Bool) -> Double {
        let remainingFiveHour = remainingFraction(for: account.usage.fiveHour)
        let remainingWeekly = remainingFraction(for: account.usage.weekly)

        let fiveHourUrgency = urgency(
            remainingFraction: remainingFiveHour,
            resetDate: account.usage.fiveHour.resetsAt,
            horizonHours: 5,
            now: now
        )
        let weeklyUrgency = urgency(
            remainingFraction: remainingWeekly,
            resetDate: account.usage.weekly.resetsAt,
            horizonHours: 168,
            now: now
        )

        var score = (fiveHourUrgency * 1.15)
            + (weeklyUrgency * 0.85)
            + (remainingFiveHour * 0.20)
            + (remainingWeekly * 0.12)

        if isCurrent {
            score += currentAccountStickyBonus
        }

        return score
    }

    private static func expiryAwareReason(candidate: AccountUsage, current: AccountUsage, now: Date) -> String {
        let candidateFiveHourUrgency = urgency(
            remainingFraction: remainingFraction(for: candidate.usage.fiveHour),
            resetDate: candidate.usage.fiveHour.resetsAt,
            horizonHours: 5,
            now: now
        )
        let currentFiveHourUrgency = urgency(
            remainingFraction: remainingFraction(for: current.usage.fiveHour),
            resetDate: current.usage.fiveHour.resetsAt,
            horizonHours: 5,
            now: now
        )

        if candidateFiveHourUrgency > currentFiveHourUrgency {
            return "\(candidate.name) has 5h headroom that is more likely to expire unused."
        }

        return "\(candidate.name) is better positioned to use weekly quota before it resets."
    }

    private static func remainingFraction(for metric: UsageMetric) -> Double {
        guard let usedPercent = metric.usedPercent else {
            return 0
        }
        return max(0, min(1, 1 - (usedPercent / 100)))
    }

    private static func urgency(
        remainingFraction: Double,
        resetDate: Date?,
        horizonHours: Double,
        now: Date
    ) -> Double {
        guard remainingFraction > 0, let resetDate else {
            return 0
        }

        let hoursRemaining = max(0, resetDate.timeIntervalSince(now) / 3_600)
        let normalized = max(0, 1 - min(hoursRemaining, horizonHours) / horizonHours)
        return remainingFraction * normalized
    }
}
