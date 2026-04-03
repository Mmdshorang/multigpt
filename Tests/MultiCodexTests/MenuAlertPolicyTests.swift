import XCTest
@testable import MultiCodex

final class MenuAlertPolicyTests: XCTestCase {
    func testRuntimeAlertHasHighestPriority() {
        let alert = MenuAlertPolicy.prioritizedAlert(
            isRuntimeAvailable: false,
            runtimeSummary: "runtime missing",
            lastRefreshError: "refresh failed",
            accountsNeedingLogin: [sampleAccount(name: "alpha")]
        )

        XCTAssertEqual(alert?.severity, .runtimeUnavailable)
        XCTAssertEqual(alert?.action, .openRuntimeSettings)
    }

    func testRefreshAlertComesBeforeAuthAlert() {
        let alert = MenuAlertPolicy.prioritizedAlert(
            isRuntimeAvailable: true,
            runtimeSummary: nil,
            lastRefreshError: "refresh failed",
            accountsNeedingLogin: [sampleAccount(name: "alpha")]
        )

        XCTAssertEqual(alert?.severity, .refreshError)
        XCTAssertEqual(alert?.action, .refreshLive)
    }

    func testAuthAlertWhenOnlyLoginIssueExists() {
        let alert = MenuAlertPolicy.prioritizedAlert(
            isRuntimeAvailable: true,
            runtimeSummary: nil,
            lastRefreshError: nil,
            accountsNeedingLogin: [sampleAccount(name: "alpha")]
        )

        XCTAssertEqual(alert?.severity, .authRequired)
        XCTAssertEqual(alert?.action, .relogin(accountName: "alpha"))
    }

    private func sampleAccount(name: String) -> AccountUsage {
        AccountUsage(
            name: name,
            isCurrent: false,
            hasAuth: false,
            lastUsedAt: nil,
            lastLoginStatus: nil,
            usage: UsageSummary(
                fiveHour: UsageMetric(label: "5h", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil),
                weekly: UsageMetric(label: "weekly", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil),
                credits: "-"
            ),
            source: "-",
            usageError: nil
        )
    }
}
