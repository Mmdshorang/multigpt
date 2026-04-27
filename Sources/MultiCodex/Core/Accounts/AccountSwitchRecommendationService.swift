import Foundation

struct AccountSwitchRecommendation: Equatable {
    let previousAccountName: String?
    let accountName: String
    let reason: String
}

enum AccountSwitchRecommendationService {
    private static let failoverFiveHourLimitPercent = 95.0
    private static let failoverWeeklyLimitPercent = 98.0
    private static let expiryAwareMargin = 0.22
    private static let paceAwareMargin = 0.15
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
        case .paceAware:
            return paceAwareRecommendation(accounts: accounts, now: now)
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
                previousAccountName: nil,
                accountName: candidate.name,
                reason: "No active account"
            )
        }

        if current.connectionState == .needsLogin {
            return AccountSwitchRecommendation(
                previousAccountName: current.name,
                accountName: candidate.name,
                reason: "Needs login"
            )
        }

        if current.connectionState == .error {
            return AccountSwitchRecommendation(
                previousAccountName: current.name,
                accountName: candidate.name,
                reason: "Refresh error"
            )
        }

        if isEffectivelyExhausted(current) {
            return AccountSwitchRecommendation(
                previousAccountName: current.name,
                accountName: candidate.name,
                reason: "Near limit"
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
                previousAccountName: nil,
                accountName: best.account.name,
                reason: "Best available fit"
            )
        }

        guard let currentScore = scored.first(where: { $0.account.name == current.name })?.score else {
            return AccountSwitchRecommendation(
                previousAccountName: current.name,
                accountName: best.account.name,
                reason: "Current account unavailable"
            )
        }

        guard best.account.name != current.name else {
            return nil
        }

        guard best.score > currentScore + expiryAwareMargin else {
            return nil
        }

        let reason = expiryAwareReason(candidate: best.account, current: current, now: now)
        return AccountSwitchRecommendation(
            previousAccountName: current.name,
            accountName: best.account.name,
            reason: reason
        )
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

        var score = (remainingFiveHour * 0.65) + (remainingWeekly * 0.35)

        // Credits bonus: accounts with credits have more headroom
        if let balance = parseCreditsBalance(account.usage.credits), balance > 0 {
            score += min(0.15, balance * 0.001)
        }

        return score
    }

    private static func parseCreditsBalance(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == "-" || cleaned == "none" || cleaned == "unlimited" || cleaned.isEmpty { return nil }
        return Double(cleaned)
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
            return "5h window expiring"
        }

        return "Weekly window expiring"
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

    // MARK: - Pace-Aware Strategy

    private static func paceAwareRecommendation(
        accounts: [AccountUsage],
        now: Date
    ) -> AccountSwitchRecommendation? {
        let current = accounts.first(where: { $0.isCurrent })
        let candidates = eligibleAccounts(from: accounts)
        guard !candidates.isEmpty else {
            return nil
        }

        let scored = candidates.map { account in
            (
                account: account,
                score: paceAwareScore(for: account, now: now, isCurrent: account.name == current?.name)
            )
        }

        guard let best = scored.max(by: { $0.score < $1.score }) else {
            return nil
        }

        guard let current else {
            return AccountSwitchRecommendation(
                previousAccountName: nil,
                accountName: best.account.name,
                reason: "Best available fit"
            )
        }

        guard let currentScore = scored.first(where: { $0.account.name == current.name })?.score else {
            return AccountSwitchRecommendation(
                previousAccountName: current.name,
                accountName: best.account.name,
                reason: "Current account unavailable"
            )
        }

        guard best.account.name != current.name else {
            return nil
        }

        guard best.score > currentScore + paceAwareMargin else {
            return nil
        }

        let reason: String
        if let pace = current.fiveHourPace, pace.isAhead {
            reason = "Current burning fast (\(pace.summaryText.lowercased()))"
        } else if let pace = best.account.fiveHourPace, pace.isOnTrack || pace.isBehind {
            reason = "Better burn rate available"
        } else {
            reason = expiryAwareReason(candidate: best.account, current: current, now: now)
        }

        return AccountSwitchRecommendation(
            previousAccountName: current.name,
            accountName: best.account.name,
            reason: reason
        )
    }

    private static func paceAwareScore(for account: AccountUsage, now: Date, isCurrent: Bool) -> Double {
        let baseScore = expiryAwareScore(for: account, now: now, isCurrent: isCurrent)

        var bonus: Double = 0
        if let pace = account.fiveHourPace ?? account.weeklyPace {
            switch pace.stage {
            case .farBehind, .behind:
                bonus += 0.10
            case .slightlyBehind, .onTrack:
                bonus += 0.05
            case .slightlyAhead:
                bonus -= 0.03
            case .ahead:
                bonus -= 0.08
            case .farAhead:
                bonus -= 0.15
            }
        }

        if let probability = account.fiveHourPace?.runOutProbability, probability > 0.5 {
            bonus -= Double(probability) * 0.12
        }

        return baseScore + bonus
    }
}
