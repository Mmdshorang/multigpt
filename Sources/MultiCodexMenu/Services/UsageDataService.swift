import Foundation

enum UsageDataService {
    static func mergeProfiles(
        accounts: AccountsListPayload,
        limits: LimitsPayload,
        previousProfiles: [ProfileUsage] = []
    ) -> [ProfileUsage] {
        let resultByAccount = Dictionary(uniqueKeysWithValues: limits.results.map { ($0.account, $0) })
        let errorsByAccount = Dictionary(uniqueKeysWithValues: limits.errors.map { ($0.account, $0.message) })
        let previousByAccount = Dictionary(uniqueKeysWithValues: previousProfiles.map { ($0.name, $0) })

        let mapped = accounts.accounts.map { account in
            let result = resultByAccount[account.name]
            let usageError = errorsByAccount[account.name]
            let previous = previousByAccount[account.name]
            let shouldKeepPreviousUsage = result == nil && usageError != nil && previous != nil
            let preservedUsage = shouldKeepPreviousUsage ? previous : nil
            let usage = preservedUsage?.usage ?? UsageFormatter.usageSummary(from: result?.snapshot)
            let source = preservedUsage?.source ?? UsageFormatter.sourceLabel(from: result)
            let effectiveUsageError = preservedUsage == nil ? usageError : nil

            return ProfileUsage(
                name: account.name,
                isCurrent: account.isCurrent || account.name == accounts.currentAccount,
                hasAuth: account.hasAuth,
                lastUsedAt: account.lastUsedAt,
                lastLoginStatus: account.lastLoginStatus,
                usage: usage,
                source: source,
                usageError: effectiveUsageError
            )
        }

        return mapped.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent {
                return lhs.isCurrent
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
