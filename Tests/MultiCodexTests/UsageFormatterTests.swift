import XCTest
@testable import MultiCodex

final class UsageFormatterTests: XCTestCase {
    func testUsageSummaryMapsWindowsAndFormatsCredits() {
        let snapshot = RateLimitSnapshot(
            primary: RateLimitWindow(usedPercent: 87.5, windowDurationMins: 300, resetsAt: Date().addingTimeInterval(3600).timeIntervalSince1970),
            secondary: RateLimitWindow(usedPercent: 12, windowDurationMins: 10_080, resetsAt: Date().addingTimeInterval(7200).timeIntervalSince1970),
            credits: CreditsSnapshot(hasCredits: true, unlimited: false, balance: "42")
        )

        let summary = UsageFormatter.usageSummary(from: snapshot)

        XCTAssertEqual(summary.fiveHour.percentText, "87.5%")
        XCTAssertEqual(summary.weekly.percentText, "12%")
        XCTAssertEqual(summary.credits, "42")
        XCTAssertNotNil(summary.fiveHour.resetsAt)
        XCTAssertNotNil(summary.weekly.resetsAt)
    }

    func testSourceLabelAndResetTextModes() {
        let result = LimitsResult(
            account: "alpha",
            source: "cached",
            snapshot: nil,
            ageSec: 12
        )
        XCTAssertEqual(UsageFormatter.sourceLabel(from: result), "cached 12s")

        let now = Date()
        let reset = now.addingTimeInterval(3600)
        let relative = UsageFormatter.resetText(for: reset, mode: .relative, now: now)
        let absolute = UsageFormatter.resetText(for: reset, mode: .absolute, now: now)

        XCTAssertTrue(relative.hasPrefix("Resets"))
        XCTAssertTrue(absolute.hasPrefix("Resets"))
        XCTAssertEqual(UsageFormatter.resetText(for: nil, mode: .relative), "-")
    }
}
