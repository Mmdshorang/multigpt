import XCTest
@testable import MultiCodex

final class AuthSwapServiceTests: XCTestCase {
    func testAtomicRenameProducesValidResult() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-swap-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let codexDir = (tempDir as NSString).appendingPathComponent(".codex")
        try fm.createDirectory(atPath: codexDir, withIntermediateDirectories: true)

        let targetAuth = Data("{\"tokens\":{\"access_token\":\"new\"}}".utf8)
        let stagedPath = (codexDir as NSString).appendingPathComponent("auth.json.staged-test")
        let authPath = (codexDir as NSString).appendingPathComponent("auth.json")

        try targetAuth.write(to: URL(fileURLWithPath: stagedPath), options: .atomic)

        // Use POSIX rename for atomicity
        let result = stagedPath.withCString { src in
            authPath.withCString { dst in
                rename(src, dst)
            }
        }
        XCTAssertEqual(result, 0)

        let readBack = try Data(contentsOf: URL(fileURLWithPath: authPath))
        XCTAssertEqual(readBack, targetAuth)
    }

    func testSwitchMissingTargetAuthPreservesSystemAuth() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-swap-missing-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let paths = CodexAccountService.PathContext(
            homeDir: tempDir,
            multicodexHome: (tempDir as NSString).appendingPathComponent("config")
        )
        try fm.createDirectory(atPath: paths.defaultCodexHome, withIntermediateDirectories: true)
        let systemAuthPath = paths.defaultCodexAuthPath
        try Data("{\"tokens\":{\"access_token\":\"keep\"}}".utf8).write(to: URL(fileURLWithPath: systemAuthPath))

        XCTAssertThrowsError(
            try AuthSwapService.switchToAccount(named: "missing", previousAccountName: "prev", paths: paths)
        )

        let after = try Data(contentsOf: URL(fileURLWithPath: systemAuthPath))
        XCTAssertTrue(String(data: after, encoding: .utf8)?.contains("keep") == true)
    }

    func testClearSystemAuthRemovesFileWhenPresent() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-clear-auth-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let paths = CodexAccountService.PathContext(
            homeDir: tempDir,
            multicodexHome: (tempDir as NSString).appendingPathComponent("config")
        )
        try fm.createDirectory(atPath: paths.defaultCodexHome, withIntermediateDirectories: true)
        try Data("{\"tokens\":{\"access_token\":\"x\"}}".utf8).write(to: URL(fileURLWithPath: paths.defaultCodexAuthPath))

        try AuthSwapService.clearSystemAuth(paths: paths)
        XCTAssertFalse(fm.fileExists(atPath: paths.defaultCodexAuthPath))
    }

    func testSwitchBlocksWhenPreviousStoredAuthIsMissing() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-missing-prev-auth-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let paths = CodexAccountService.PathContext(
            homeDir: tempDir,
            multicodexHome: (tempDir as NSString).appendingPathComponent("config")
        )
        try fm.createDirectory(atPath: paths.defaultCodexHome, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: paths.accountDir("alpha"), withIntermediateDirectories: true)
        try fm.createDirectory(atPath: paths.accountDir("beta"), withIntermediateDirectories: true)

        let systemAuth = authJSON(accountID: "acct_alpha", email: "alpha@example.com", marker: "only-system-copy")
        let betaAuth = authJSON(accountID: "acct_beta", email: "beta@example.com", marker: "beta")
        try Data(systemAuth.utf8).write(to: URL(fileURLWithPath: paths.defaultCodexAuthPath))
        try Data(betaAuth.utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("beta")))

        XCTAssertThrowsError(
            try AuthSwapService.switchToAccount(named: "beta", previousAccountName: "alpha", paths: paths)
        )

        let systemAfter = try String(contentsOfFile: paths.defaultCodexAuthPath, encoding: .utf8)
        XCTAssertTrue(systemAfter.contains("only-system-copy"))
        XCTAssertFalse(systemAfter.contains("beta"))
        XCTAssertFalse(fm.fileExists(atPath: paths.accountAuthPath("alpha")))
    }

    func testForceSwitchDoesNotPreserveSystemAuthWhenProviderAccountIDsDiffer() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-force-identity-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let paths = CodexAccountService.PathContext(
            homeDir: tempDir,
            multicodexHome: (tempDir as NSString).appendingPathComponent("config")
        )
        try fm.createDirectory(atPath: paths.defaultCodexHome, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: paths.accountDir("alpha"), withIntermediateDirectories: true)
        try fm.createDirectory(atPath: paths.accountDir("beta"), withIntermediateDirectories: true)

        let alphaAuth = authJSON(accountID: "acct_alpha", email: "dev@example.com", marker: "alpha-original")
        let externalAuth = authJSON(accountID: "acct_external", email: "dev@example.com", marker: "external")
        let betaAuth = authJSON(accountID: "acct_beta", email: "beta@example.com", marker: "beta")
        try Data(alphaAuth.utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("alpha")))
        try Data(externalAuth.utf8).write(to: URL(fileURLWithPath: paths.defaultCodexAuthPath))
        try Data(betaAuth.utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("beta")))

        try AuthSwapService.switchToAccount(
            named: "beta",
            previousAccountName: "alpha",
            paths: paths,
            force: true
        )

        let alphaAfter = try String(contentsOfFile: paths.accountAuthPath("alpha"), encoding: .utf8)
        let systemAfter = try String(contentsOfFile: paths.defaultCodexAuthPath, encoding: .utf8)
        XCTAssertTrue(alphaAfter.contains("alpha-original"))
        XCTAssertFalse(alphaAfter.contains("external"))
        XCTAssertTrue(systemAfter.contains("beta"))
    }

    func testSwitchBlocksWhenNestedProviderAccountIDsDifferWithSameEmail() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-nested-identity-block-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let paths = CodexAccountService.PathContext(
            homeDir: tempDir,
            multicodexHome: (tempDir as NSString).appendingPathComponent("config")
        )
        try fm.createDirectory(atPath: paths.defaultCodexHome, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: paths.accountDir("alpha"), withIntermediateDirectories: true)
        try fm.createDirectory(atPath: paths.accountDir("beta"), withIntermediateDirectories: true)

        let alphaAuth = authJSONWithNestedAccountID(accountID: "acct_alpha", email: "dev@example.com", marker: "alpha-original")
        let externalAuth = authJSONWithNestedAccountID(accountID: "acct_external", email: "dev@example.com", marker: "external")
        let betaAuth = authJSONWithNestedAccountID(accountID: "acct_beta", email: "beta@example.com", marker: "beta")
        try Data(alphaAuth.utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("alpha")))
        try Data(externalAuth.utf8).write(to: URL(fileURLWithPath: paths.defaultCodexAuthPath))
        try Data(betaAuth.utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("beta")))

        XCTAssertThrowsError(
            try AuthSwapService.switchToAccount(named: "beta", previousAccountName: "alpha", paths: paths)
        )

        let alphaAfter = try String(contentsOfFile: paths.accountAuthPath("alpha"), encoding: .utf8)
        let systemAfter = try String(contentsOfFile: paths.defaultCodexAuthPath, encoding: .utf8)
        XCTAssertTrue(alphaAfter.contains("alpha-original"))
        XCTAssertFalse(alphaAfter.contains("external"))
        XCTAssertTrue(systemAfter.contains("external"))
        XCTAssertFalse(systemAfter.contains("beta"))
    }

    func testForceSwitchDoesNotPreserveSystemAuthWhenNestedProviderAccountIDsDiffer() throws {
        let tempDir = NSTemporaryDirectory() + "/mc-test-force-nested-identity-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tempDir) }

        let paths = CodexAccountService.PathContext(
            homeDir: tempDir,
            multicodexHome: (tempDir as NSString).appendingPathComponent("config")
        )
        try fm.createDirectory(atPath: paths.defaultCodexHome, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: paths.accountDir("alpha"), withIntermediateDirectories: true)
        try fm.createDirectory(atPath: paths.accountDir("beta"), withIntermediateDirectories: true)

        let alphaAuth = authJSONWithNestedAccountID(accountID: "acct_alpha", email: "dev@example.com", marker: "alpha-original")
        let externalAuth = authJSONWithNestedAccountID(accountID: "acct_external", email: "dev@example.com", marker: "external")
        let betaAuth = authJSONWithNestedAccountID(accountID: "acct_beta", email: "beta@example.com", marker: "beta")
        try Data(alphaAuth.utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("alpha")))
        try Data(externalAuth.utf8).write(to: URL(fileURLWithPath: paths.defaultCodexAuthPath))
        try Data(betaAuth.utf8).write(to: URL(fileURLWithPath: paths.accountAuthPath("beta")))

        try AuthSwapService.switchToAccount(
            named: "beta",
            previousAccountName: "alpha",
            paths: paths,
            force: true
        )

        let alphaAfter = try String(contentsOfFile: paths.accountAuthPath("alpha"), encoding: .utf8)
        let systemAfter = try String(contentsOfFile: paths.defaultCodexAuthPath, encoding: .utf8)
        XCTAssertTrue(alphaAfter.contains("alpha-original"))
        XCTAssertFalse(alphaAfter.contains("external"))
        XCTAssertTrue(systemAfter.contains("beta"))
    }

    private func authJSON(accountID: String, email: String, marker: String) -> String {
        """
        {
          "marker": "\(marker)",
          "tokens": {
            "account_id": "\(accountID)",
            "access_token": "\(makeJWT(email: email))"
          }
        }
        """
    }

    private func authJSONWithNestedAccountID(accountID: String, email: String, marker: String) -> String {
        """
        {
          "marker": "\(marker)",
          "tokens": {
            "access_token": "\(makeJWT(claims: [
                "email": email,
                "https://api.openai.com/auth": ["chatgpt_account_id": accountID],
            ]))"
          }
        }
        """
    }

    private func makeJWT(email: String) -> String {
        makeJWT(claims: ["email": email])
    }

    private func makeJWT(claims: [String: Any]) -> String {
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payloadData = try! JSONSerialization.data(withJSONObject: claims, options: [])
        return "\(header).\(base64URL(payloadData)).signature"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
