import XCTest
@testable import MultiCodex

final class PaceAwareRecommendationTests: XCTestCase {
    func testPaceAwareSwitchesFromFastBurningAccount() {
        let now = Date()
        // Account A (current): 90% used, only 10% elapsed → burning very fast (farAhead)
        // Account B: 10% used, 90% elapsed → conserving well (farBehind)
        let accounts = [
            makeAccount("A", isCurrent: true, fiveHourUsed: 90, fiveHourResetsIn: 270 * 60, weeklyUsed: 10),
            makeAccount("B", isCurrent: false, fiveHourUsed: 10, fiveHourResetsIn: 30 * 60, weeklyUsed: 10),
        ]

        let rec = AccountSwitchRecommendationService.recommendation(
            for: .paceAware,
            accounts: accounts,
            now: now
        )
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.accountName, "B")
        XCTAssertNotEqual(rec?.accountName, "A")
    }

    func testPaceAwareDoesNotSwitchWhenOnTrack() {
        let now = Date()
        // Both accounts at 50% with 50% time remaining → on track, no switch
        let accounts = [
            makeAccount("A", isCurrent: true, fiveHourUsed: 50, fiveHourResetsIn: 150 * 60, weeklyUsed: 30),
            makeAccount("B", isCurrent: false, fiveHourUsed: 50, fiveHourResetsIn: 150 * 60, weeklyUsed: 30),
        ]

        let rec = AccountSwitchRecommendationService.recommendation(
            for: .paceAware,
            accounts: accounts,
            now: now
        )
        XCTAssertNil(rec)
    }

    private func makeAccount(_ name: String, isCurrent: Bool, fiveHourUsed: Double, fiveHourResetsIn: TimeInterval, weeklyUsed: Double) -> AccountUsage {
        AccountUsage(
            name: name,
            isCurrent: isCurrent,
            hasAuth: true,
            lastUsedAt: nil,
            lastLoginStatus: nil,
            usage: UsageSummary(
                fiveHour: UsageMetric(
                    label: "5h",
                    percentText: "\(fiveHourUsed)%",
                    usedPercent: fiveHourUsed,
                    periodMinutes: 300,
                    resetsAt: Date().addingTimeInterval(fiveHourResetsIn)
                ),
                weekly: UsageFixtures.makeUsageMetric(label: "Weekly", usedPercent: weeklyUsed),
                credits: "-"
            ),
            source: "test",
            usageError: nil
        )
    }
}
