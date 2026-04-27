import Foundation

enum AccountUsageMergeService {
    static func mergeAccounts(
        accounts: AccountsListPayload,
        limits: LimitsPayload,
        previousAccounts: [AccountUsage] = []
    ) -> [AccountUsage] {
        let resultByAccount = Dictionary(uniqueKeysWithValues: limits.results.map { ($0.account, $0) })
        let errorsByAccount = Dictionary(uniqueKeysWithValues: limits.errors.map { ($0.account, $0.message) })
        let previousByAccount = Dictionary(uniqueKeysWithValues: previousAccounts.map { ($0.name, $0) })

        let mapped = accounts.accounts.map { account in
            let result = resultByAccount[account.name]
            let usageError = errorsByAccount[account.name]
            let previous = previousByAccount[account.name]
            let shouldKeepPreviousUsage = result == nil && previous != nil
            let preservedUsage = shouldKeepPreviousUsage ? previous : nil
            let usage = preservedUsage?.usage ?? UsageFormatter.usageSummary(from: result?.snapshot)
            let source = preservedUsage?.source ?? UsageFormatter.sourceLabel(from: result)
            let effectiveUsageError = usageError

            let fiveHourPace = UsagePace.compute(
                usedPercent: usage.fiveHour.usedPercent,
                periodMinutes: usage.fiveHour.periodMinutes,
                resetsAt: usage.fiveHour.resetsAt
            )
            let weeklyPace = UsagePace.compute(
                usedPercent: usage.weekly.usedPercent,
                periodMinutes: usage.weekly.periodMinutes,
                resetsAt: usage.weekly.resetsAt
            )

            // Record historical snapshots for pace analysis
            if usage.fiveHour.usedPercent != nil {
                let store = UsagePaceStore()
                Task {
                    await store.record(
                        accountName: account.name,
                        fiveHour: usage.fiveHour,
                        weekly: usage.weekly
                    )
                }
            }

            return AccountUsage(
                name: account.name,
                isCurrent: account.isCurrent || account.name == accounts.currentAccount,
                hasAuth: account.hasAuth,
                lastUsedAt: account.lastUsedAt,
                lastLoginStatus: account.lastLoginStatus,
                defaultWorkspaceEmail: account.defaultWorkspaceEmail,
                usage: usage,
                source: source,
                usageError: effectiveUsageError,
                fiveHourPace: fiveHourPace,
                weeklyPace: weeklyPace
            )
        }

        return mapped
    }
}
