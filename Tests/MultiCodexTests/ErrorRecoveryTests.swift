import XCTest
@testable import MultiCodex

final class ErrorRecoveryTests: XCTestCase {
    func testExtractJSONObjectHandlesNestedBracesAndStrings() throws {
        let service = CodexAccountService()
        let extracted = try XCTUnwrap(service.extractJSONObject(after: "body=", in: "prefix body={\"a\":{\"b\":\"} not end\"}} suffix"))
        XCTAssertEqual(extracted, #"{"a":{"b":"} not end"}}"#)
    }

    func testRecoverSnapshotFromRPCErrorBody() throws {
        let service = CodexAccountService()
        let error = "request failed body={\"rate_limit\":{\"primary_window\":{\"used_percent\":99.7,\"reset_after_seconds\":60},\"secondary_window\":{\"used_percent\":42,\"limit_window_seconds\":604800}},\"credits\":{\"has_credits\":true,\"unlimited\":false,\"balance\":12.5}}"

        let snapshot = try XCTUnwrap(service.recoverSnapshotFromRPCError(error))

        XCTAssertEqual(snapshot.primary?.usedPercent, 99.7)
        XCTAssertEqual(snapshot.primary?.windowDurationMins, 300)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 42)
        XCTAssertEqual(snapshot.secondary?.windowDurationMins, 10_080)
        XCTAssertEqual(snapshot.credits?.hasCredits, true)
        XCTAssertEqual(snapshot.credits?.unlimited, false)
        XCTAssertEqual(snapshot.credits?.balance, "12.5")
    }
}
