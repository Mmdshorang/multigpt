import XCTest
@testable import MultiCodexMenu

@MainActor
final class AccountsMenuViewModelTests: XCTestCase {
    func testSetLimitsCacheTTLUpdatesServiceAndPreferences() {
        let defaults = ephemeralDefaults()
        let preferences = AppPreferencesStore(defaults: defaults)
        let service = MockCodexAccountService()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: preferences,
            startImmediately: false
        )

        viewModel.setLimitsCacheTTLSeconds(5)

        XCTAssertEqual(viewModel.limitsCacheTTLSeconds, CodexAccountService.minLimitsCacheTTLSeconds)
        XCTAssertEqual(service.limitsCacheTTLSeconds, CodexAccountService.minLimitsCacheTTLSeconds)

        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.limitsCacheTTLSeconds, CodexAccountService.minLimitsCacheTTLSeconds)
    }

    func testSelectSettingsSectionPersistsSelection() {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.selectSettingsSection(.runtime)

        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.selectedSettingsSection, .runtime)
    }

    func testUpdateCustomCodexPathUpdatesServiceAndStore() {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.updateCustomCodexPath(" /usr/local/bin/codex ")

        XCTAssertEqual(service.customCodexPath, "/usr/local/bin/codex")
        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.customCodexPath, "/usr/local/bin/codex")
    }

    func testExecutePendingAccountRemovalRequiresTypedNameWhenDeletingData() async {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.beginAccountRemoval(named: "alpha", deleteData: true)
        viewModel.executePendingAccountRemoval(confirming: "wrong")

        XCTAssertEqual(viewModel.pendingAccountRemovalRequest?.accountName, "alpha")
        XCTAssertEqual(viewModel.accountActionError, "Type the account name to confirm delete-data removal.")
        XCTAssertEqual(service.removeCalls.count, 0)
    }

    func testExecutePendingAccountRemovalRunsRemovalWhenTypedNameMatches() async {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.beginAccountRemoval(named: "alpha", deleteData: true)
        viewModel.executePendingAccountRemoval(confirming: "alpha")

        await waitUntil(timeoutSeconds: 1.0) {
            !service.removeCalls.isEmpty
        }

        XCTAssertNil(viewModel.pendingAccountRemovalRequest)
        XCTAssertEqual(service.removeCalls.first?.name, "alpha")
        XCTAssertEqual(service.removeCalls.first?.deleteData, true)
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "MultiCodexTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func waitUntil(timeoutSeconds: TimeInterval, condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

private final class MockCodexAccountService: CodexAccountServicing {
    struct RemoveCall {
        let name: String
        let deleteData: Bool
    }

    var customCodexPath: String?
    var sandboxHomeDirectory: String?
    var sandboxMulticodexHomeDirectory: String?
    var limitsCacheTTLSeconds: Int = CodexAccountService.defaultLimitsCacheTTLSeconds
    var resolutionHint: String?
    var stubbedAccounts: [AccountEntry] = []
    private(set) var removeCalls: [RemoveCall] = []

    func fetchAccounts() async throws -> AccountsListPayload {
        let current = stubbedAccounts.first(where: { $0.isCurrent })?.name
        return AccountsListPayload(accounts: stubbedAccounts, currentAccount: current)
    }

    func fetchLimits(refreshLive _: Bool) async throws -> LimitsPayload {
        LimitsPayload(results: [], errors: [])
    }

    func switchAccount(name _: String) async throws {}

    func removeAccount(name: String, deleteData: Bool) async throws -> RemoveAccountPayload {
        removeCalls.append(RemoveCall(name: name, deleteData: deleteData))
        return RemoveAccountPayload(removedAccount: name, currentAccount: nil)
    }

    func renameAccount(from oldName: String, to newName: String) async throws -> RenameAccountPayload {
        RenameAccountPayload(from: oldName, to: newName, currentAccount: nil)
    }

    func importDefaultAuth(into name: String) async throws -> ImportAccountPayload {
        ImportAccountPayload(account: name)
    }

    func fetchStatus(name: String) async throws -> AccountStatusPayload {
        AccountStatusPayload(
            account: name,
            exitCode: 0,
            stdout: "",
            stderr: "",
            output: "ok",
            checkedAt: ""
        )
    }

    func openLoginInTerminal(account _: String) throws {}

    func openNewAccountLoginInTerminal(newAccountName _: String) throws {}

    func loginInApp(account _: String, createIfNeeded _: Bool) async throws -> String {
        "ok"
    }

    func effectiveMulticodexHomePath() -> String {
        "/tmp"
    }

    func probeRuntime() -> CodexAccountService.RuntimeProbe {
        CodexAccountService.RuntimeProbe(isAvailable: true, summary: "ok")
    }
}
