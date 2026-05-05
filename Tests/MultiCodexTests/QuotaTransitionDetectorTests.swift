import XCTest
@testable import MultiCodex

final class QuotaTransitionDetectorTests: XCTestCase {
    func testDetectsDepletedAndRestoredTransitions() {
        let previous = [
            account("alpha", fiveHourUsed: 80, weeklyUsed: 99.8),
            account("beta", fiveHourUsed: 99.8, weeklyUsed: 40),
        ]
        let current = [
            account("alpha", fiveHourUsed: 99.6, weeklyUsed: 75),
            account("beta", fiveHourUsed: 50, weeklyUsed: 40),
        ]

        let transitions = QuotaTransitionDetector.detectTransitions(previous: previous, current: current)

        XCTAssertEqual(transitions.count, 3)
        XCTAssertTrue(transitions.contains(.init(accountName: "alpha", window: .fiveHour, transition: .depleted)))
        XCTAssertTrue(transitions.contains(.init(accountName: "alpha", window: .weekly, transition: .restored)))
        XCTAssertTrue(transitions.contains(.init(accountName: "beta", window: .fiveHour, transition: .restored)))
    }

    func testDoesNotEmitTransitionsForInitialRefresh() {
        XCTAssertTrue(QuotaTransitionDetector.detectTransitions(previous: [], current: [account("alpha", fiveHourUsed: 99.8)]).isEmpty)
    }

    private func account(_ name: String, fiveHourUsed: Double? = 20, weeklyUsed: Double? = 20) -> AccountUsage {
        AccountUsage(
            name: name,
            isCurrent: false,
            hasAuth: true,
            lastUsedAt: nil,
            lastLoginStatus: nil,
            usage: UsageSummary(
                fiveHour: UsageFixtures.makeUsageMetric(label: "5h", usedPercent: fiveHourUsed),
                weekly: UsageFixtures.makeUsageMetric(label: "Weekly", usedPercent: weeklyUsed),
                credits: "-"
            ),
            source: "test",
            usageError: nil
        )
    }
}
