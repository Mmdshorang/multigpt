import XCTest
@testable import MultiCodex

final class CostScannerTests: XCTestCase {
    func testScanEmptyDirectoryReturnsZero() {
        let tempDir = NSTemporaryDirectory() + "/mc-test-scan-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let result = CostUsageScanner.scan(directory: URL(fileURLWithPath: tempDir))
        XCTAssertEqual(result.totalCostUSD, 0)
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.totalInputTokens, 0)
        XCTAssertEqual(result.totalOutputTokens, 0)
    }

    func testScanParsesJSONLEntries() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-scan-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let jsonl = """
        {"model":"gpt-5-codex","usage":{"input_tokens":1000,"output_tokens":500,"cached_input_tokens":200},"timestamp":"2026-04-27T12:00:00Z"}
        {"model":"gpt-5","usage":{"input_tokens":2000,"output_tokens":1000},"timestamp":"2026-04-20T12:00:00Z"}
        """
        let jsonlPath = (tempDir as NSString).appendingPathComponent("session.jsonl")
        try Data(jsonl.utf8).write(to: URL(fileURLWithPath: jsonlPath))

        let now = ISO8601DateFormatter().date(from: "2026-04-27T18:00:00Z")!
        let result = CostUsageScanner.scan(directory: URL(fileURLWithPath: tempDir), now: now)

        XCTAssertEqual(result.entries.count, 2)
        XCTAssertTrue(result.totalCostUSD > 0)
        XCTAssertTrue(result.todayCostUSD > 0)
        XCTAssertEqual(result.totalInputTokens, 3000)
        XCTAssertEqual(result.totalOutputTokens, 1500)
    }
}
