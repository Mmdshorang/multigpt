import AppKit
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

    func testPerformRefreshHandlesFirstFailureThenWarningFallback() async {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        service.fetchAccountsError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "accounts unavailable"])
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.refresh()

        await waitUntil(timeoutSeconds: 1.0) {
            viewModel.lastRefreshError != nil
        }

        XCTAssertEqual(viewModel.lastRefreshError, "accounts unavailable")
        XCTAssertNil(viewModel.refreshWarningMessage)

        service.fetchAccountsError = nil
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [LimitsResult(account: "alpha", source: "live-api", snapshot: nil, ageSec: nil)],
            errors: []
        )

        viewModel.refreshLive()
        await waitUntil(timeoutSeconds: 1.0) {
            viewModel.accounts.count == 1 && viewModel.lastRefreshError == nil
        }

        service.fetchLimitsError = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "limits failed"])
        viewModel.refresh()

        await waitUntil(timeoutSeconds: 1.0) {
            viewModel.refreshWarningMessage == "Refresh failed. Showing latest data."
        }

        XCTAssertNil(viewModel.lastRefreshError)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha"])
    }

    func testTemporaryAuthSandboxToggleUpdatesEnvironmentAndPreferences() async throws {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.setTemporaryAuthSandboxEnabled(true)

        await waitUntil(timeoutSeconds: 1.0) {
            viewModel.isUsingTemporaryAuthSandbox && service.sandboxHomeDirectory != nil
        }

        XCTAssertTrue(viewModel.isUsingTemporaryAuthSandbox)
        let sandboxHome = try XCTUnwrap(viewModel.temporaryAuthSandboxHome)
        XCTAssertEqual(service.sandboxHomeDirectory, sandboxHome)
        XCTAssertEqual(
            service.sandboxMulticodexHomeDirectory,
            (sandboxHome as NSString).appendingPathComponent(".config/multicodex")
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: (sandboxHome as NSString).appendingPathComponent(".config/multicodex")
            )
        )

        let persistedEnabled = AppPreferencesStore(defaults: defaults)
        XCTAssertTrue(persistedEnabled.temporaryAuthSandboxEnabled)
        XCTAssertEqual(persistedEnabled.temporaryAuthSandboxHome, sandboxHome)

        viewModel.setTemporaryAuthSandboxEnabled(false)
        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.isUsingTemporaryAuthSandbox
        }

        XCTAssertNil(service.sandboxHomeDirectory)
        XCTAssertNil(service.sandboxMulticodexHomeDirectory)
        let persistedDisabled = AppPreferencesStore(defaults: defaults)
        XCTAssertFalse(persistedDisabled.temporaryAuthSandboxEnabled)
    }

    func testStartLoginFlowFallsBackToTerminalAndRecoversOnAppActive() async {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.loginInAppError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "stdin not interactive"])

        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.openLoginInTerminal(for: "alpha")

        await waitUntil(timeoutSeconds: 1.0) {
            service.openLoginCalls.contains("alpha")
        }

        XCTAssertEqual(service.openLoginCalls, ["alpha"])
        XCTAssertTrue((viewModel.accountActionMessage ?? "").contains("Terminal fallback"))

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        await waitUntil(timeoutSeconds: 1.0) {
            service.importCalls.contains("alpha") && service.statusCalls.contains("alpha")
        }

        XCTAssertTrue(service.importCalls.contains("alpha"))
        XCTAssertTrue(service.statusCalls.contains("alpha"))
    }

    func testOnboardingStateTransitionsMatrix() async {
        let runtimeOffService = MockCodexAccountService()
        runtimeOffService.probeRuntimeResult = CodexAccountService.RuntimeProbe(isAvailable: false, summary: "missing runtime")
        let runtimeOff = AccountsMenuViewModel(
            accountService: runtimeOffService,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: ephemeralDefaults()),
            startImmediately: false
        )
        XCTAssertEqual(runtimeOff.onboardingState.step, .runtime)

        let emptyService = MockCodexAccountService()
        emptyService.probeRuntimeResult = CodexAccountService.RuntimeProbe(isAvailable: true, summary: "ok")
        let empty = AccountsMenuViewModel(
            accountService: emptyService,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: ephemeralDefaults()),
            startImmediately: false
        )
        XCTAssertEqual(empty.onboardingState.step, .login)

        let needsLoginService = MockCodexAccountService()
        needsLoginService.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: false, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        let needsLogin = AccountsMenuViewModel(
            accountService: needsLoginService,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: ephemeralDefaults()),
            startImmediately: false
        )
        needsLogin.refresh()
        await waitUntil(timeoutSeconds: 1.0) {
            !needsLogin.accounts.isEmpty
        }
        XCTAssertEqual(needsLogin.onboardingState.step, .verify)

        let completeService = MockCodexAccountService()
        completeService.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        let complete = AccountsMenuViewModel(
            accountService: completeService,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: ephemeralDefaults()),
            startImmediately: false
        )
        complete.refresh()
        await waitUntil(timeoutSeconds: 1.0) {
            !complete.accounts.isEmpty
        }
        XCTAssertEqual(complete.onboardingState.step, .done)
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
    struct LoginCall {
        let account: String
        let createIfNeeded: Bool
    }

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
    var stubbedLimits: LimitsPayload = LimitsPayload(results: [], errors: [])
    var fetchAccountsError: Error?
    var fetchLimitsError: Error?
    var switchError: Error?
    var removeError: Error?
    var renameError: Error?
    var importError: Error?
    var fetchStatusError: Error?
    var openLoginError: Error?
    var openNewLoginError: Error?
    var loginInAppError: Error?
    var probeRuntimeResult = CodexAccountService.RuntimeProbe(isAvailable: true, summary: "ok")

    private(set) var switchCalls: [String] = []
    private(set) var removeCalls: [RemoveCall] = []
    private(set) var renameCalls: [(from: String, to: String)] = []
    private(set) var importCalls: [String] = []
    private(set) var statusCalls: [String] = []
    private(set) var openLoginCalls: [String] = []
    private(set) var openNewLoginCalls: [String] = []
    private(set) var loginInAppCalls: [LoginCall] = []

    func fetchAccounts() async throws -> AccountsListPayload {
        if let fetchAccountsError {
            throw fetchAccountsError
        }
        let current = stubbedAccounts.first(where: { $0.isCurrent })?.name
        return AccountsListPayload(accounts: stubbedAccounts, currentAccount: current)
    }

    func fetchLimits(refreshLive _: Bool) async throws -> LimitsPayload {
        if let fetchLimitsError {
            throw fetchLimitsError
        }
        return stubbedLimits
    }

    func switchAccount(name: String) async throws {
        switchCalls.append(name)
        if let switchError {
            throw switchError
        }
    }

    func removeAccount(name: String, deleteData: Bool) async throws -> RemoveAccountPayload {
        if let removeError {
            throw removeError
        }
        removeCalls.append(RemoveCall(name: name, deleteData: deleteData))
        return RemoveAccountPayload(removedAccount: name, currentAccount: nil)
    }

    func renameAccount(from oldName: String, to newName: String) async throws -> RenameAccountPayload {
        if let renameError {
            throw renameError
        }
        renameCalls.append((from: oldName, to: newName))
        return RenameAccountPayload(from: oldName, to: newName, currentAccount: nil)
    }

    func importDefaultAuth(into name: String) async throws -> ImportAccountPayload {
        if let importError {
            throw importError
        }
        importCalls.append(name)
        return ImportAccountPayload(account: name)
    }

    func fetchStatus(name: String) async throws -> AccountStatusPayload {
        if let fetchStatusError {
            throw fetchStatusError
        }
        statusCalls.append(name)
        return AccountStatusPayload(
            account: name,
            exitCode: 0,
            stdout: "",
            stderr: "",
            output: "ok",
            checkedAt: ""
        )
    }

    func openLoginInTerminal(account name: String) throws {
        if let openLoginError {
            throw openLoginError
        }
        openLoginCalls.append(name)
    }

    func openNewAccountLoginInTerminal(newAccountName name: String) throws {
        if let openNewLoginError {
            throw openNewLoginError
        }
        openNewLoginCalls.append(name)
    }

    func loginInApp(account name: String, createIfNeeded: Bool) async throws -> String {
        loginInAppCalls.append(LoginCall(account: name, createIfNeeded: createIfNeeded))
        if let loginInAppError {
            throw loginInAppError
        }
        return "ok"
    }

    func effectiveMulticodexHomePath() -> String {
        "/tmp"
    }

    func probeRuntime() -> CodexAccountService.RuntimeProbe {
        probeRuntimeResult
    }
}
