import XCTest
@testable import MultiCodex

final class AccountUsageMergeServiceTests: XCTestCase {
    func testMergeAccountsPreservesPreviousUsageAndErrorOnPerAccountRefreshFailure() {
        let previous = AccountUsage(
            name: "alpha",
            isCurrent: true,
            hasAuth: true,
            lastUsedAt: nil,
            lastLoginStatus: nil,
            usage: UsageSummary(
                fiveHour: UsageMetric(label: "5h", percentText: "35%", usedPercent: 35, periodMinutes: 300, resetsAt: nil),
                weekly: UsageMetric(label: "weekly", percentText: "50%", usedPercent: 50, periodMinutes: 10_080, resetsAt: nil),
                credits: "unlimited"
            ),
            source: "cached 30s",
            usageError: nil
        )

        let merged = AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(
                accounts: [
                    AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
                ],
                currentAccount: "alpha"
            ),
            limits: LimitsPayload(
                results: [],
                errors: [
                    LimitsErrorEntry(account: "alpha", message: "rate limit endpoint unavailable"),
                ]
            ),
            previousAccounts: [previous]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].usage.fiveHour.percentText, "35%")
        XCTAssertEqual(merged[0].source, "cached 30s")
        XCTAssertEqual(merged[0].usageError, "rate limit endpoint unavailable")
    }

    func testMergeAccountsPreservesPayloadOrderAndMarksCurrent() {
        let merged = AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(
                accounts: [
                    AccountEntry(name: "charlie", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
                    AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
                    AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
                ],
                currentAccount: "alpha"
            ),
            limits: LimitsPayload(results: [], errors: [])
        )

        XCTAssertEqual(merged.map(\.name), ["charlie", "beta", "alpha"])
        XCTAssertEqual(merged.last?.isCurrent, true)
    }

    func testMergeAccountsPreservesPreviousUsageWhileFreshResultsAreStillLoading() {
        let previous = AccountUsage(
            name: "alpha",
            isCurrent: true,
            hasAuth: true,
            lastUsedAt: nil,
            lastLoginStatus: nil,
            usage: UsageSummary(
                fiveHour: UsageMetric(label: "5h", percentText: "61%", usedPercent: 61, periodMinutes: 300, resetsAt: nil),
                weekly: UsageMetric(label: "weekly", percentText: "44%", usedPercent: 44, periodMinutes: 10_080, resetsAt: nil),
                credits: "unlimited"
            ),
            source: "live-api",
            usageError: nil
        )

        let merged = AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(
                accounts: [
                    AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
                ],
                currentAccount: "alpha"
            ),
            limits: LimitsPayload(results: [], errors: []),
            previousAccounts: [previous]
        )

        XCTAssertEqual(merged[0].usage.fiveHour.percentText, "61%")
        XCTAssertEqual(merged[0].usage.weekly.percentText, "44%")
        XCTAssertEqual(merged[0].source, "live-api")
        XCTAssertNil(merged[0].usageError)
    }
}
