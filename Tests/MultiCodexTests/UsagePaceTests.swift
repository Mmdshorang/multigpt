import XCTest
@testable import MultiCodex

final class UsagePaceTests: XCTestCase {
    private let now = Date()

    func testOnTrackWhenUsageMatchesElapsedTime() {
        // 50% used at the midpoint of a 5h window → on track
        let pace = UsagePace.compute(
            usedPercent: 50,
            periodMinutes: 300,
            resetsAt: now.addingTimeInterval(150 * 60),
            now: now
        )
        XCTAssertNotNil(pace)
        XCTAssertEqual(pace?.stage, .onTrack)
        XCTAssertNil(pace?.etaSeconds)
        XCTAssertTrue(pace?.willLastToReset == true)
    }

    func testFarAheadWhenBurningFast() {
        // 90% used after only 25% of the window → far ahead (burning fast)
        let pace = UsagePace.compute(
            usedPercent: 90,
            periodMinutes: 300,
            resetsAt: now.addingTimeInterval(225 * 60),
            now: now
        )
        XCTAssertNotNil(pace)
        XCTAssertEqual(pace?.stage, .farAhead)
        XCTAssertNotNil(pace?.etaSeconds)
        XCTAssertFalse(pace?.willLastToReset == true)
    }

    func testFarBehindWhenBarelyUsed() {
        // 10% used at 75% elapsed → far behind (conserving)
        let pace = UsagePace.compute(
            usedPercent: 10,
            periodMinutes: 300,
            resetsAt: now.addingTimeInterval(75 * 60),
            now: now
        )
        XCTAssertNotNil(pace)
        XCTAssertEqual(pace?.stage, .farBehind)
        XCTAssertTrue(pace?.willLastToReset == true)
    }

    func testReturnsNilWhenMissingData() {
        XCTAssertNil(UsagePace.compute(usedPercent: nil, periodMinutes: 300, resetsAt: now))
        XCTAssertNil(UsagePace.compute(usedPercent: 50, periodMinutes: nil, resetsAt: now))
        XCTAssertNil(UsagePace.compute(usedPercent: 50, periodMinutes: 300, resetsAt: nil))
        XCTAssertNil(UsagePace.compute(usedPercent: 50, periodMinutes: 0, resetsAt: now))
    }

    func testDetailTextCombinesSummaryAndEta() {
        let pace = UsagePace.compute(
            usedPercent: 90,
            periodMinutes: 300,
            resetsAt: now.addingTimeInterval(225 * 60),
            now: now
        )
        XCTAssertNotNil(pace)
        XCTAssertTrue(pace!.detailText.contains("deficit"))
    }
}
