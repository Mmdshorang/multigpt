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

    func testImportUsesAccountConfigMutationLock() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-import-lock-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let service = CodexAccountService()
        service.sandboxHomeDirectory = (tempDir as NSString).appendingPathComponent("home")
        service.sandboxMulticodexHomeDirectory = (tempDir as NSString).appendingPathComponent("config")
        try fm.createDirectory(atPath: service.effectiveMulticodexHomePath(), withIntermediateDirectories: true)

        let payload = AccountExportService.ExportPayload(
            version: 1,
            exportedAt: "2026-05-22T00:00:00Z",
            appVersion: "0.5.0",
            accounts: [.init(name: "beta", auth: Data("{\"tokens\":{\"access_token\":\"beta\"}}".utf8))],
            preferences: nil,
            currentAccount: nil
        )

        let exportURL = URL(fileURLWithPath: tempDir).appendingPathComponent("export.json")
        try JSONEncoder().encode(payload).write(to: exportURL)

        let started = expectation(description: "import started")
        let finished = expectation(description: "import finished")
        var importResult: AccountExportService.ImportResult?
        var importError: Error?

        try service.withConfigMutationLock {
            DispatchQueue.global(qos: .userInitiated).async {
                started.fulfill()
                do {
                    var prefs = AppPreferencesStore(defaults: makeEphemeralDefaults())
                    importResult = try AccountExportService.importAccounts(
                        from: exportURL,
                        accountService: service,
                        preferencesStore: &prefs
                    )
                } catch {
                    importError = error
                }
                finished.fulfill()
            }

            wait(for: [started], timeout: 1)
            Thread.sleep(forTimeInterval: 0.2)
            let configWhileLocked = try service.loadConfig(paths: service.currentPaths())
            XCTAssertFalse(
                configWhileLocked.accounts.contains("beta"),
                "Import mutated account config without acquiring the registry lock."
            )
        }

        wait(for: [finished], timeout: 1)
        XCTAssertNil(importError)
        XCTAssertEqual(importResult?.imported, 1)

        let finalConfig = try service.loadConfig(paths: service.currentPaths())
        XCTAssertTrue(finalConfig.accounts.contains("beta"))
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

    func testExportAuthFilesWritesEachAccountAuthJSONWith0600Permissions() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-auth-files-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let service = CodexAccountService()
        service.sandboxHomeDirectory = (tempDir as NSString).appendingPathComponent("home")
        service.sandboxMulticodexHomeDirectory = (tempDir as NSString).appendingPathComponent("config")
        try fm.createDirectory(atPath: service.effectiveMulticodexHomePath(), withIntermediateDirectories: true)
        _ = try service.addAccountNow(name: "alpha")
        _ = try service.addAccountNow(name: "beta")

        let paths = service.currentPaths()
        let migrationMarker = (paths.multicodexHome as NSString).appendingPathComponent(".managed-migration-complete")
        try Data().write(to: URL(fileURLWithPath: migrationMarker))
        try Data("{\"tokens\":{\"access_token\":\"legacy-alpha\"}}".utf8)
            .write(to: URL(fileURLWithPath: paths.accountAuthPath("alpha")))
        try Data("{\"tokens\":{\"access_token\":\"beta-token\"}}".utf8)
            .write(to: URL(fileURLWithPath: paths.accountAuthPath("beta")))
        let alphaManagedHome = try ManagedCodexHomeFactory.createHome(
            for: "alpha",
            multicodexHome: paths.multicodexHome
        )
        try ManagedCodexHomeFactory.writeAuthData(
            Data("{\"tokens\":{\"access_token\":\"managed-alpha\"}}".utf8),
            to: alphaManagedHome
        )

        let exportRoot = URL(fileURLWithPath: tempDir).appendingPathComponent("auth-export")
        let result = try AccountExportService.exportAuthFiles(to: exportRoot, accountService: service)

        XCTAssertEqual(result.exported, 2)
        XCTAssertTrue(result.skippedAccounts.isEmpty)

        let alphaURL = exportRoot.appendingPathComponent("alpha").appendingPathComponent("auth.json")
        let betaURL = exportRoot.appendingPathComponent("beta").appendingPathComponent("auth.json")
        let alphaAuth = try String(contentsOf: alphaURL, encoding: .utf8)
        let betaAuth = try String(contentsOf: betaURL, encoding: .utf8)
        XCTAssertTrue(alphaAuth.contains("managed-alpha"))
        XCTAssertFalse(alphaAuth.contains("legacy-alpha"))
        XCTAssertTrue(betaAuth.contains("beta-token"))

        let alphaPerms = (try fm.attributesOfItem(atPath: alphaURL.path)[.posixPermissions] as? NSNumber)?.intValue
        let betaPerms = (try fm.attributesOfItem(atPath: betaURL.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(alphaPerms, 0o600)
        XCTAssertEqual(betaPerms, 0o600)
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

    func testImportOverwriteUpdatesManagedAuthWhenMigrationComplete() throws {
        let tempDir = NSTemporaryDirectory() + "mc-test-import-managed-\(UUID().uuidString)"
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
        let managedHome = try ManagedCodexHomeFactory.createHome(for: "alpha", multicodexHome: paths.multicodexHome)
        try ManagedCodexHomeFactory.writeAuthData(Data("{\"tokens\":{\"access_token\":\"old-managed\"}}".utf8), to: managedHome)

        let payload = AccountExportService.ExportPayload(
            version: 1,
            exportedAt: "2026-05-22T00:00:00Z",
            appVersion: "0.5.0",
            accounts: [.init(name: "alpha", auth: Data("{\"tokens\":{\"access_token\":\"imported\"}}".utf8))],
            preferences: nil,
            currentAccount: "alpha"
        )
        let exportURL = URL(fileURLWithPath: tempDir).appendingPathComponent("managed-import.json")
        try JSONEncoder().encode(payload).write(to: exportURL)
        var prefs = AppPreferencesStore(defaults: makeEphemeralDefaults())

        let result = try AccountExportService.importAccounts(
            from: exportURL,
            accountService: service,
            preferencesStore: &prefs,
            mergeStrategy: .overwrite
        )

        XCTAssertEqual(result.imported, 1)
        let legacyAuth = try String(contentsOfFile: paths.accountAuthPath("alpha"), encoding: .utf8)
        let managedAuth = String(data: try XCTUnwrap(ManagedCodexHomeFactory.readAuthData(from: managedHome)), encoding: .utf8)
        XCTAssertTrue(legacyAuth.contains("imported"))
        XCTAssertTrue(managedAuth?.contains("imported") == true)
        XCTAssertFalse(managedAuth?.contains("old-managed") == true)
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
