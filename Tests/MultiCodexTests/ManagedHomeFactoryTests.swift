import XCTest
@testable import MultiCodex

final class ManagedHomeFactoryTests: XCTestCase {
    func testCreateAndRetrieveHome() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-homes-\(UUID().uuidString)"
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: tempDir) }

        let rootURL = URL(fileURLWithPath: tempDir)
        let accountName = "TestAccount"
        let sanitized = ManagedCodexHomeFactory.sanitize(accountName)

        let homeURL = rootURL.appendingPathComponent(sanitized, isDirectory: true)
        try fm.createDirectory(at: homeURL, withIntermediateDirectories: true)

        XCTAssertTrue(fm.fileExists(atPath: homeURL.path))
    }

    func testSanitizeRemovesDangerousCharacters() {
        XCTAssertEqual(ManagedCodexHomeFactory.sanitize("a/b\\c:d*e?f\"g<h>i|j"), "abcdefghij")
    }

    func testWriteAndReadAuthData() throws {
        let homeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mc-test-auth-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(atPath: homeURL.path) }

        let testData = Data("{\"test\":true}".utf8)
        try ManagedCodexHomeFactory.writeAuthData(testData, to: homeURL)

        let readBack = try ManagedCodexHomeFactory.readAuthData(from: homeURL)
        XCTAssertEqual(readBack, testData)
    }

    func testValidateSafeDeletionRejectsRootPath() {
        XCTAssertThrowsError(
            try ManagedCodexHomeFactory.validateSafeDeletion(
                ManagedCodexHomeFactory.defaultRootURL()
            )
        )
    }
}
