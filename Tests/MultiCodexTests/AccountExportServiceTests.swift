import XCTest
@testable import MultiCodex

final class AccountExportServiceTests: XCTestCase {
    func testExportAndImportRoundTrip() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-export-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        // Set up service with sandbox
        let service = CodexAccountService()
        service.sandboxHomeDirectory = (tempDir as NSString).appendingPathComponent("home")
        service.sandboxMulticodexHomeDirectory = (tempDir as NSString).appendingPathComponent("config")
        try fm.createDirectory(atPath: service.effectiveMulticodexHomePath(), withIntermediateDirectories: true)

        // Add accounts with auth
        _ = try service.addAccountNow(name: "alpha")
        _ = try service.addAccountNow(name: "beta")

        let alphaAuthPath = (service.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/alpha/auth.json")
        let betaAuthPath = (service.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/beta/auth.json")
        try Data("{\"tokens\":{\"access_token\":\"alpha-token\"}}".utf8).write(to: URL(fileURLWithPath: alphaAuthPath))
        try Data("{\"tokens\":{\"access_token\":\"beta-token\"}}".utf8).write(to: URL(fileURLWithPath: betaAuthPath))

        var prefs = AppPreferencesStore(defaults: makeEphemeralDefaults())

        // Export
        let exportData = try AccountExportService.exportData(
            accountService: service,
            preferencesStore: prefs
        )
        let exportURL = URL(fileURLWithPath: tempDir).appendingPathComponent("export.json")
        try exportData.write(to: exportURL)

        // Import into fresh config
        let service2 = CodexAccountService()
        service2.sandboxHomeDirectory = (tempDir as NSString).appendingPathComponent("home2")
        service2.sandboxMulticodexHomeDirectory = (tempDir as NSString).appendingPathComponent("config2")
        try fm.createDirectory(atPath: service2.effectiveMulticodexHomePath(), withIntermediateDirectories: true)

        let result = try AccountExportService.importAccounts(
            from: exportURL,
            accountService: service2,
            preferencesStore: &prefs
        )

        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(result.conflicts.isEmpty)

        // Verify auth data was restored
        let importedAlphaPath = (service2.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/alpha/auth.json")
        let importedData = try Data(contentsOf: URL(fileURLWithPath: importedAlphaPath))
        let parsed = try JSONSerialization.jsonObject(with: importedData) as? [String: Any]
        let tokens = parsed?["tokens"] as? [String: Any]
        XCTAssertEqual(tokens?["access_token"] as? String, "alpha-token")
    }
}
