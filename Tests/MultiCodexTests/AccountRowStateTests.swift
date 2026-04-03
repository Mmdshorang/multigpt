import XCTest
@testable import MultiCodex

final class AccountRowStateTests: XCTestCase {
    func testPrimaryActionReflectsConnectionState() {
        let connectedCurrent = makeAccount(name: "alpha", isCurrent: true, hasAuth: true, usageError: nil)
        let connectedNotCurrent = makeAccount(name: "beta", isCurrent: false, hasAuth: true, usageError: nil)
        let needsLogin = makeAccount(name: "gamma", isCurrent: false, hasAuth: false, usageError: nil)
        let errorState = makeAccount(name: "delta", isCurrent: false, hasAuth: true, usageError: "refresh failed")

        XCTAssertEqual(
            AccountRowState(account: connectedCurrent, resetDisplayMode: .relative).primaryAction,
            .none
        )
        XCTAssertEqual(
            AccountRowState(account: connectedNotCurrent, resetDisplayMode: .relative).primaryAction,
            .switchAccount
        )
        XCTAssertEqual(
            AccountRowState(account: needsLogin, resetDisplayMode: .relative).primaryAction,
            .relogin
        )
        XCTAssertEqual(
            AccountRowState(account: errorState, resetDisplayMode: .relative).primaryAction,
            .switchAccount
        )
    }

    private func makeAccount(name: String, isCurrent: Bool, hasAuth: Bool, usageError: String?) -> AccountUsage {
        AccountUsage(
            name: name,
            isCurrent: isCurrent,
            hasAuth: hasAuth,
            lastUsedAt: nil,
            lastLoginStatus: nil,
            usage: UsageSummary(
                fiveHour: UsageMetric(label: "5h", percentText: "20%", usedPercent: 20, periodMinutes: 300, resetsAt: nil),
                weekly: UsageMetric(label: "weekly", percentText: "10%", usedPercent: 10, periodMinutes: 10_080, resetsAt: nil),
                credits: "100"
            ),
            source: "live-api",
            usageError: usageError
        )
    }
}
