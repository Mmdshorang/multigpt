import XCTest
@testable import MultiCodexMenu

final class AccountUsageMergeServiceTests: XCTestCase {
    func testMergeAccountsPreservesPreviousUsageOnPerAccountRefreshFailure() {
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
        XCTAssertNil(merged[0].usageError)
    }

    func testMergeAccountsSortsCurrentFirstThenByName() {
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

        XCTAssertEqual(merged.map(\.name), ["alpha", "beta", "charlie"])
    }
}
