import XCTest
@testable import MultiCodex

final class CodexAccountServiceTests: XCTestCase {
    func testNormalizedLimitsCacheTTLSecondsClampsBounds() {
        XCTAssertEqual(CodexAccountService.normalizedLimitsCacheTTLSeconds(1), CodexAccountService.minLimitsCacheTTLSeconds)
        XCTAssertEqual(CodexAccountService.normalizedLimitsCacheTTLSeconds(100_000), CodexAccountService.maxLimitsCacheTTLSeconds)

        let mid = 900
        XCTAssertEqual(CodexAccountService.normalizedLimitsCacheTTLSeconds(mid), mid)
    }

    func testAddAccountNormalizesNameAndRejectsInvalidCharacters() async throws {
        let service = makeSandboxedService()

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

    func testAddAccountForLoginDoesNotSelectItAsCurrent() throws {
        let service = makeSandboxedService()

        _ = try service.addAccountIfNeededForLoginNow(name: "alpha")

        let configPath = (service.effectiveMulticodexHomePath() as NSString).appendingPathComponent("config.json")
        let configData = try XCTUnwrap(FileManager.default.contents(atPath: configPath))
        let config = try AccountConfigStore.decodeConfig(from: configData)

        XCTAssertNil(config.currentAccount)
        XCTAssertEqual(config.accounts, Set(["alpha"]))
    }

    func testImportAuthFromHomeCopiesSandboxAuthWithoutTouchingDefaultAuth() async throws {
        let service = makeSandboxedService()
        _ = try service.addAccountIfNeededForLoginNow(name: "alpha")

        let sandbox = try XCTUnwrap(service.sandboxHomeDirectory)
        let loginHome = makeSandboxDirectory()
        let defaultAuthPath = (sandbox as NSString).appendingPathComponent(".codex/auth.json")
        let loginAuthPath = (loginHome as NSString).appendingPathComponent(".codex/auth.json")
        let accountAuthPath = (service.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/alpha/auth.json")

        try writeText("{\"tokens\":{\"access_token\":\"external\"}}\n", to: defaultAuthPath)
        try writeText("{\"tokens\":{\"access_token\":\"sandbox\"}}\n", to: loginAuthPath)

        _ = try await service.importAuth(fromHome: loginHome, into: "alpha")

        let defaultAfter = try String(contentsOfFile: defaultAuthPath, encoding: .utf8)
        let accountAfter = try String(contentsOfFile: accountAuthPath, encoding: .utf8)
        XCTAssertTrue(defaultAfter.contains("external"))
        XCTAssertTrue(accountAfter.contains("sandbox"))
    }

    func testFetchAccountsInfersDefaultWorkspaceEmailFromAuthToken() async throws {
        let service = makeSandboxedService()
        _ = try await service.addAccount(name: "alpha")

        let authPath = (service.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/alpha/auth.json")
        let idToken = makeIDToken(email: "dev@example.com", defaultWorkspace: "Personal")
        try writeText(
            """
            {
              "tokens": {
                "access_token": "token",
                "id_token": "\(idToken)"
              }
            }
            """,
            to: authPath
        )

        let payload = try await service.fetchAccounts()
        XCTAssertEqual(payload.accounts.first?.defaultWorkspaceEmail, "dev@example.com")
    }

    func testFetchAccountsIgnoresAccountIDForWorkspaceEmailFormatting() async throws {
        let service = makeSandboxedService()
        _ = try await service.addAccount(name: "alpha")

        let authPath = (service.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/alpha/auth.json")
        let idToken = makeIDToken(email: "dev@example.com", defaultWorkspace: "Personal")
        try writeText(
            """
            {
              "tokens": {
                "access_token": "token",
                "id_token": "\(idToken)",
                "account_id": "85b6d406-11f4-4e7f-a354-566b54bb63bc"
              }
            }
            """,
            to: authPath
        )

        let payload = try await service.fetchAccounts()
        XCTAssertEqual(payload.accounts.first?.defaultWorkspaceEmail, "dev@example.com")
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
        let service = makeSandboxedService()
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
        let service = makeSandboxedService()
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
        let service = makeSandboxedService()

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
        let gammaMeta = try JSONDecoder().decode(CodexAccountService.AccountMeta.self, from: gammaMetaData)
        XCTAssertNotNil(gammaMeta.updatedAt)

        let removedAlphaDir = (service.effectiveMulticodexHomePath() as NSString).appendingPathComponent("accounts/alpha")
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedAlphaDir))
    }

    func testRemoveCurrentAccountAppliesNextAccountAuthToDefault() async throws {
        let service = makeSandboxedService()
        let sandbox = try XCTUnwrap(service.sandboxHomeDirectory)

        _ = try await service.addAccount(name: "alpha")
        _ = try await service.addAccount(name: "beta")
        try await service.switchAccount(name: "alpha")

        let defaultAuthPath = (sandbox as NSString).appendingPathComponent(".codex/auth.json")
        let betaAuthPath = (service.effectiveMulticodexHomePath() as NSString)
            .appendingPathComponent("accounts/beta/auth.json")

        try writeText("{\"tokens\":{\"access_token\":\"alpha-token\"}}\n", to: defaultAuthPath)
        try writeText("{\"tokens\":{\"access_token\":\"beta-token\"}}\n", to: betaAuthPath)

        _ = try await service.removeAccount(name: "alpha", deleteData: false)

        let defaultAfter = try String(contentsOfFile: defaultAuthPath, encoding: .utf8)
        XCTAssertTrue(defaultAfter.contains("beta-token"))

        let configPath = (service.effectiveMulticodexHomePath() as NSString).appendingPathComponent("config.json")
        let configData = try XCTUnwrap(FileManager.default.contents(atPath: configPath))
        let config = try AccountConfigStore.decodeConfig(from: configData)
        XCTAssertEqual(config.currentAccount, "beta")
    }

    func testRemoveLastCurrentAccountClearsDefaultAuth() async throws {
        let service = makeSandboxedService()
        let sandbox = try XCTUnwrap(service.sandboxHomeDirectory)

        _ = try await service.addAccount(name: "alpha")
        try await service.switchAccount(name: "alpha")

        let defaultAuthPath = (sandbox as NSString).appendingPathComponent(".codex/auth.json")
        try writeText("{\"tokens\":{\"access_token\":\"alpha-token\"}}\n", to: defaultAuthPath)

        _ = try await service.removeAccount(name: "alpha", deleteData: false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: defaultAuthPath))

        let configPath = (service.effectiveMulticodexHomePath() as NSString).appendingPathComponent("config.json")
        let configData = try XCTUnwrap(FileManager.default.contents(atPath: configPath))
        let config = try AccountConfigStore.decodeConfig(from: configData)
        XCTAssertNil(config.currentAccount)
        XCTAssertTrue(config.accounts.isEmpty)
    }

    func testFetchStatusRestoresDefaultAuthAfterCommandFailure() async throws {
        let service = makeSandboxedService()
        service.customCodexPath = "/not/a/real/codex/path"

        let sandbox = try XCTUnwrap(service.sandboxHomeDirectory)

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

    func testBaseEnvironmentMergesLoginShellPathAheadOfGuiPath() {
        let service = CodexAccountService()
        configureEnvironment(
            for: service,
            path: "/usr/bin:/bin",
            loginShellPath: "/Users/tester/.bun/bin:/Users/tester/.local/share/mise/installs/node/24.13.0/bin:/usr/bin"
        )

        let environment = service.baseEnvironment()
        let pathComponents = (environment["PATH"] ?? "").split(separator: ":").map(String.init)

        XCTAssertEqual(pathComponents.prefix(2), [
            "/Users/tester/.bun/bin",
            "/Users/tester/.local/share/mise/installs/node/24.13.0/bin",
        ])
        XCTAssertEqual(pathComponents.filter { $0 == "/usr/bin" }.count, 1)
        XCTAssertTrue(pathComponents.contains("/opt/homebrew/bin"))
    }

    func testResolveCodexRuntimeAutoDetectsExecutableFromLoginShellPath() throws {
        let service = CodexAccountService()
        let binDirectory = URL(fileURLWithPath: makeSandboxDirectory(), isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let codexPath = try makeExecutable(named: "codex", in: binDirectory)

        configureEnvironment(for: service, path: "/usr/bin:/bin", loginShellPath: binDirectory.path)

        let runtime = try service.resolveCodexRuntime()

        XCTAssertEqual(runtime.executableURL.path, codexPath)
        XCTAssertEqual(runtime.prefixArguments, [])
        XCTAssertTrue(runtime.display.contains("(from which)"))
    }

    private func makeSandboxedService() -> CodexAccountService {
        let service = CodexAccountService()
        let sandbox = makeSandboxDirectory()
        service.sandboxHomeDirectory = sandbox
        service.sandboxMulticodexHomeDirectory = (sandbox as NSString).appendingPathComponent(".config/multicodex")
        return service
    }

    private func configureEnvironment(
        for service: CodexAccountService,
        path: String,
        loginShellPath: String,
        home: String = "/Users/tester"
    ) {
        service.processEnvironmentProvider = {
            [
                "PATH": path,
                "HOME": home,
            ]
        }
        service.loginShellPathResolver = { _ in loginShellPath }
    }

    private func makeSandboxDirectory() -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("multicodex-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }

    private func makeExecutable(named name: String, in directory: URL) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let executableURL = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )
        return executableURL.path
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

    private func makeIDToken(email: String, defaultWorkspace: String) -> String {
        let header: [String: Any] = [
            "alg": "none",
            "typ": "JWT",
        ]
        let payload: [String: Any] = [
            "email": email,
            "https://api.openai.com/auth": [
                "organizations": [
                    [
                        "title": defaultWorkspace,
                        "is_default": true,
                    ],
                ],
            ],
        ]

        let headerSegment = base64URLEncodedJSON(header)
        let payloadSegment = base64URLEncodedJSON(payload)
        return "\(headerSegment).\(payloadSegment).signature"
    }

    private func base64URLEncodedJSON(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
