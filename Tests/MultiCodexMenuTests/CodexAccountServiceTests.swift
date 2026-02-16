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

    func testAccountConfigStoreDecodesLegacyVersion1Format() throws {
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

        XCTAssertEqual(record.currentAccount, "alpha")
        XCTAssertEqual(record.accounts, Set(["alpha", "beta"]))
    }

    private func makeSandboxDirectory() -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("multicodex-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.path
    }
}
