import XCTest
@testable import MultiCodex

final class TokenRefreshTests: XCTestCase {
    func testRefreshStaleTokensDoesNotCrashWithNoAccounts() {
        let service = CodexAccountService()
        service.sandboxHomeDirectory = NSTemporaryDirectory() + "/mc-test-token-\(UUID().uuidString)/home"
        service.sandboxMulticodexHomeDirectory = NSTemporaryDirectory() + "/mc-test-token-\(UUID().uuidString)/config"
        try? FileManager.default.createDirectory(atPath: service.effectiveMulticodexHomePath(), withIntermediateDirectories: true)

        let errors = service.refreshStaleTokens()
        XCTAssertTrue(errors.isEmpty)
    }

    func testRefreshStaleTokensSkipsAccountsWithoutAuth() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-token-\(UUID().uuidString)"
        let service = CodexAccountService()
        service.sandboxHomeDirectory = (tempDir as NSString).appendingPathComponent("home")
        service.sandboxMulticodexHomeDirectory = (tempDir as NSString).appendingPathComponent("config")
        try FileManager.default.createDirectory(atPath: service.effectiveMulticodexHomePath(), withIntermediateDirectories: true)

        _ = try service.addAccountNow(name: "alpha")
        // No auth file written — should be skipped

        let errors = service.refreshStaleTokens()
        XCTAssertTrue(errors.isEmpty, "Should skip accounts without auth")
    }
}
