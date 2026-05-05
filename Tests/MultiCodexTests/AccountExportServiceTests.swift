import XCTest
@testable import MultiCodex

final class AccountExportServiceTests: XCTestCase {
    func testImportRejectsPathTraversalAccountName() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-import-traversal-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let service = CodexAccountService()
        service.sandboxHomeDirectory = (tempDir as NSString).appendingPathComponent("home")
        service.sandboxMulticodexHomeDirectory = (tempDir as NSString).appendingPathComponent("config")
        try fm.createDirectory(atPath: service.effectiveMulticodexHomePath(), withIntermediateDirectories: true)

        let payload = AccountExportService.ExportPayload(
            version: 1,
            exportedAt: "2026-05-03T00:00:00Z",
            appVersion: "0.5.0",
            accounts: [.init(name: "../../escaped", auth: Data("{}".utf8))],
            preferences: nil,
            currentAccount: nil
        )

        let exportURL = URL(fileURLWithPath: tempDir).appendingPathComponent("bad-export.json")
        try JSONEncoder().encode(payload).write(to: exportURL)
        var prefs = AppPreferencesStore(defaults: makeEphemeralDefaults())

        XCTAssertThrowsError(
            try AccountExportService.importAccounts(
                from: exportURL,
                accountService: service,
                preferencesStore: &prefs
            )
        )
    }

    func testWriteBackupDataUses0600Permissions() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-export-perms-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let fileURL = URL(fileURLWithPath: tempDir).appendingPathComponent("backup.json")
        try AccountExportService.writeBackupData(Data("{}".utf8), to: fileURL)
        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)
    }

    func testExportPrefersManagedAuthWhenMigrationComplete() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-export-managed-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let service = CodexAccountService()
        service.sandboxHomeDirectory = (tempDir as NSString).appendingPathComponent("home")
        service.sandboxMulticodexHomeDirectory = (tempDir as NSString).appendingPathComponent("config")
        try fm.createDirectory(atPath: service.effectiveMulticodexHomePath(), withIntermediateDirectories: true)
        _ = try service.addAccountNow(name: "alpha")
        let paths = service.currentPaths()
        try Data().write(to: URL(fileURLWithPath: (paths.multicodexHome as NSString).appendingPathComponent(".managed-migration-complete")))
        try Data("{\"tokens\":{\"access_token\":\"legacy\"}}".utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("alpha")))
        let managedHome = try ManagedCodexHomeFactory.createHome(for: "alpha", multicodexHome: paths.multicodexHome)
        try ManagedCodexHomeFactory.writeAuthData(Data("{\"tokens\":{\"access_token\":\"managed\"}}".utf8), to: managedHome)

        let data = try AccountExportService.exportData(accountService: service, preferencesStore: AppPreferencesStore(defaults: makeEphemeralDefaults()))
        let payload = try JSONDecoder().decode(AccountExportService.ExportPayload.self, from: data)
        let authString = String(data: payload.accounts.first!.auth, encoding: .utf8)
        XCTAssertTrue(authString?.contains("managed") == true)
    }

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
