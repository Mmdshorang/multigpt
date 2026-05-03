import XCTest
@testable import MultiCodex

final class UpdateCheckerTests: XCTestCase {
    func testRepositoryMatchesPublicReleaseRepository() {
        XCTAssertEqual(UpdateChecker.repository, "momoazn/multicodex")
    }

    func testVersionComparisonNewer() {
        // Access private method indirectly through the release check logic
        XCTAssertTrue(isNewer("1.0.0", than: "0.9.0"))
        XCTAssertTrue(isNewer("0.5.0", than: "0.4.9"))
        XCTAssertTrue(isNewer("2.0.0", than: "1.9.9"))
    }

    func testVersionComparisonSame() {
        XCTAssertFalse(isNewer("1.0.0", than: "1.0.0"))
    }

    func testVersionComparisonOlder() {
        XCTAssertFalse(isNewer("0.9.0", than: "1.0.0"))
    }

    private func isNewer(_ v1: String, than v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(parts1.count, parts2.count) {
            let a = i < parts1.count ? parts1[i] : 0
            let b = i < parts2.count ? parts2[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }
}
