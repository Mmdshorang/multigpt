import XCTest
@testable import MultiCodexMenu

final class CodexAccountServiceTests: XCTestCase {
    func testNormalizedLimitsCacheTTLSecondsClampsBounds() {
        XCTAssertEqual(CodexAccountService.normalizedLimitsCacheTTLSeconds(1), CodexAccountService.minLimitsCacheTTLSeconds)
        XCTAssertEqual(CodexAccountService.normalizedLimitsCacheTTLSeconds(100_000), CodexAccountService.maxLimitsCacheTTLSeconds)

        let mid = 900
        XCTAssertEqual(CodexAccountService.normalizedLimitsCacheTTLSeconds(mid), mid)
    }

    func testAddAccountNormalizesNameAndRejectsInvalidCharacters() async throws {
        let service = CodexAccountService()
        let sandbox = makeSandboxDirectory()
        service.sandboxHomeDirectory = sandbox
        service.sandboxMulticodexHomeDirectory = (sandbox as NSString).appendingPathComponent(".config/multicodex")

        _ = try await service.addAccount(name: "  alpha_1  ")

        let accounts = try await service.fetchAccounts()
        XCTAssertEqual(accounts.accounts.map(\.name), ["alpha_1"])

        do {
            _ = try await service.addAccount(name: "bad name")
            XCTFail("Expected invalid account name error")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.localizedCaseInsensitiveContains("invalid account name"),
                "Unexpected error: \(error.localizedDescription)"
            )
        }
    }

    func testAccountConfigStoreRejectsLegacyVersion1Format() throws {
        let json = """
        {
          "version": 1,
          "currentAccount": "alpha",
          "accounts": {
            "alpha": {},
            "beta": {}
          }
        }
        """
        let record = try AccountConfigStore.decodeConfig(from: Data(json.utf8))

        XCTAssertNil(record.currentAccount)
        XCTAssertEqual(record.accounts, [])
    }

    func testFetchLimitsUsesCachedSnapshotWhenTTLIsValid() async throws {
        let service = CodexAccountService()
        let sandbox = makeSandboxDirectory()
        service.sandboxHomeDirectory = sandbox
        service.sandboxMulticodexHomeDirectory = (sandbox as NSString).appendingPathComponent(".config/multicodex")
        service.limitsCacheTTLSeconds = 600

        _ = try await service.addAccount(name: "alpha")
        try seedCachedLimits(multicodexHome: service.effectiveMulticodexHomePath(), account: "alpha", ageSeconds: 5)

        let limits = try await service.fetchLimits(refreshLive: false)

        XCTAssertEqual(limits.errors.count, 0)
        XCTAssertEqual(limits.results.count, 1)
        XCTAssertEqual(limits.results.first?.account, "alpha")
        XCTAssertEqual(limits.results.first?.source, "cached")
        XCTAssertNotNil(limits.results.first?.snapshot?.primary?.usedPercent)
    }

    func testFetchLimitsReportsApiThenRpcFallbackFailure() async throws {
        let service = CodexAccountService()
        let sandbox = makeSandboxDirectory()
        service.sandboxHomeDirectory = sandbox
        service.sandboxMulticodexHomeDirectory = (sandbox as NSString).appendingPathComponent(".config/multicodex")
        service.customCodexPath = "/not/a/real/codex/path"

        _ = try await service.addAccount(name: "alpha")

        let accountAuthPath = (service.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/alpha/auth.json")
        try writeText(
            """
            {
              "tokens": {
                "access_token": "invalid-token",
                "refresh_token": "invalid-refresh"
              },
              "last_refresh": "2001-01-01T00:00:00Z"
            }
            """,
            to: accountAuthPath
        )

        let limits = try await service.fetchLimits(refreshLive: true)

        XCTAssertEqual(limits.results.count, 0)
        XCTAssertEqual(limits.errors.count, 1)
        XCTAssertTrue(limits.errors[0].message.contains("API failed"))
        XCTAssertTrue(limits.errors[0].message.contains("RPC fallback failed"))
    }

    func testSwitchRenameRemoveUpdateConfigAndMeta() async throws {
        let service = CodexAccountService()
        let sandbox = makeSandboxDirectory()
        service.sandboxHomeDirectory = sandbox
        service.sandboxMulticodexHomeDirectory = (sandbox as NSString).appendingPathComponent(".config/multicodex")

        _ = try await service.addAccount(name: "alpha")
        _ = try await service.addAccount(name: "beta")
        try await service.switchAccount(name: "beta")
        _ = try await service.renameAccount(from: "beta", to: "gamma")
        _ = try await service.removeAccount(name: "alpha", deleteData: true)

        let configPath = (service.effectiveMulticodexHomePath() as NSString).appendingPathComponent("config.json")
        let configData = try XCTUnwrap(FileManager.default.contents(atPath: configPath))
        let config = try AccountConfigStore.decodeConfig(from: configData)
        XCTAssertEqual(config.currentAccount, "gamma")
        XCTAssertEqual(config.accounts, Set(["gamma"]))

        let gammaMetaPath = (service.effectiveMulticodexHomePath() as NSString).appendingPathComponent("accounts/gamma/meta.json")
        let gammaMetaData = try XCTUnwrap(FileManager.default.contents(atPath: gammaMetaPath))
        let gammaMeta = try JSONSerialization.jsonObject(with: gammaMetaData) as? [String: Any]
        XCTAssertNotNil(gammaMeta?["updatedAt"] as? String)

        let removedAlphaDir = (service.effectiveMulticodexHomePath() as NSString).appendingPathComponent("accounts/alpha")
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedAlphaDir))
    }

    func testFetchStatusRestoresDefaultAuthAfterCommandFailure() async throws {
        let service = CodexAccountService()
        let sandbox = makeSandboxDirectory()
        service.sandboxHomeDirectory = sandbox
        service.sandboxMulticodexHomeDirectory = (sandbox as NSString).appendingPathComponent(".config/multicodex")
        service.customCodexPath = "/not/a/real/codex/path"

        _ = try await service.addAccount(name: "alpha")

        let homeCodexDir = (sandbox as NSString).appendingPathComponent(".codex")
        let defaultAuthPath = (homeCodexDir as NSString).appendingPathComponent("auth.json")
        let accountAuthPath = (service.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/alpha/auth.json")

        try writeText("{\"tokens\":{\"access_token\":\"default\"}}\n", to: defaultAuthPath)
        try writeText("{\"tokens\":{\"access_token\":\"account\"}}\n", to: accountAuthPath)

        do {
            _ = try await service.fetchStatus(name: "alpha")
            XCTFail("Expected fetchStatus to fail with invalid runtime.")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        let defaultAfter = try String(contentsOfFile: defaultAuthPath, encoding: .utf8)
        XCTAssertTrue(defaultAfter.contains("default"))
    }

    private func makeSandboxDirectory() -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("multicodex-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    private func seedCachedLimits(multicodexHome: String, account: String, ageSeconds: Double) throws {
        let cachePath = (multicodexHome as NSString).appendingPathComponent("limits-cache.json")
        let fetchedAtMs = Date().timeIntervalSince1970 * 1000 - (ageSeconds * 1000)
        let json = """
        {
          "version": 1,
          "accounts": {
            "\(account)": {
              "snapshot": {
                "primary": {
                  "usedPercent": 42,
                  "windowDurationMins": 300,
                  "resetsAt": 4102444800
                },
                "secondary": {
                  "usedPercent": 18,
                  "windowDurationMins": 10080,
                  "resetsAt": 4102444800
                },
                "credits": {
                  "hasCredits": true,
                  "unlimited": false,
                  "balance": "100"
                }
              },
              "fetchedAt": \(fetchedAtMs),
              "provider": "api"
            }
          }
        }
        """
        try writeText(json, to: cachePath)
    }

    private func writeText(_ value: String, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try Data(value.utf8).write(to: URL(fileURLWithPath: path))
    }
}
