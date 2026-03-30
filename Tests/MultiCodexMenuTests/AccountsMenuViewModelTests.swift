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

    func testSwitchingStrategyDefaultsToManualAndPersistsChanges() {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        XCTAssertEqual(viewModel.accountSwitchingStrategy, .manual)
        XCTAssertFalse(viewModel.autoSwitchNotificationsEnabled)

        viewModel.setAccountSwitchingStrategy(.expiryAware)
        viewModel.setAutoSwitchNotificationsEnabled(true)

        XCTAssertEqual(viewModel.accountSwitchingStrategy, .expiryAware)
        XCTAssertTrue(viewModel.autoSwitchNotificationsEnabled)
        XCTAssertEqual(notifier.authorizationRequests, 1)
        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.accountSwitchingStrategy, .expiryAware)
        XCTAssertTrue(persisted.autoSwitchNotificationsEnabled)
    }

    func testSelectSettingsSectionPersistsSelection() {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
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

        let previousFiveHour = viewModel.accounts.first?.usage.fiveHour.percentText

        service.fetchLimitsError = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "limits failed"])
        viewModel.refresh()

        await waitUntil(timeoutSeconds: 1.0) {
            viewModel.refreshWarningMessage == "Refresh failed. Showing latest data."
        }

        XCTAssertNil(viewModel.lastRefreshError)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha"])
        XCTAssertEqual(viewModel.accounts.first?.usage.fiveHour.percentText, previousFiveHour)
    }

    func testPerformRefreshPublishesAccountsBeforeSlowLimitsComplete() async throws {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [LimitsResult(account: "alpha", source: "live-api", snapshot: nil, ageSec: nil)],
            errors: []
        )
        service.fetchLimitsDelayNanoseconds = 400_000_000

        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha"])
        XCTAssertTrue(viewModel.isRefreshing)
    }

    func testManualStrategyDoesNotAutoSwitch() async {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: false, lastUsedAt: nil, lastLoginStatus: "expired"),
            AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 10, weeklyUsed: 10), ageSec: nil),
                LimitsResult(account: "beta", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 20, weeklyUsed: 20), ageSec: nil),
            ],
            errors: []
        )

        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.refreshLive()

        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.accounts.isEmpty
        }

        XCTAssertTrue(service.switchCalls.isEmpty)
    }

    func testFailoverStrategyAutomaticallySwitchesWhenCurrentNeedsLogin() async {
        let defaults = ephemeralDefaults()
        var preferences = AppPreferencesStore(defaults: defaults)
        preferences.accountSwitchingStrategy = .failover

        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: false, lastUsedAt: nil, lastLoginStatus: "expired"),
            AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 40, weeklyUsed: 40), ageSec: nil),
                LimitsResult(account: "beta", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 15, weeklyUsed: 25), ageSec: nil),
            ],
            errors: []
        )

        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: preferences,
            startImmediately: false
        )

        viewModel.refreshLive()

        await waitUntil(timeoutSeconds: 1.0) {
            service.switchCalls.contains("beta")
        }

        XCTAssertEqual(service.switchCalls.last, "beta")
        XCTAssertEqual(viewModel.accountActionMessage, "Auto-switched alpha -> beta. Needs login.")
        XCTAssertTrue(notifier.sentPayloads.isEmpty)
    }

    func testFailoverStrategyAutomaticallySwitchesWhenCurrentRefreshErrorsButUsageIsPreserved() async {
        let defaults = ephemeralDefaults()
        var preferences = AppPreferencesStore(defaults: defaults)
        preferences.accountSwitchingStrategy = .failover

        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
            AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "beta", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 15, weeklyUsed: 15), ageSec: nil),
            ],
            errors: [
                LimitsErrorEntry(account: "alpha", message: "Codex RPC timed out"),
            ]
        )

        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: preferences,
            startImmediately: false
        )
        viewModel.accounts = [
            AccountUsage(
                name: "alpha",
                isCurrent: true,
                hasAuth: true,
                lastUsedAt: nil,
                lastLoginStatus: nil,
                usage: UsageSummary(
                    fiveHour: UsageMetric(label: "5h", percentText: "40%", usedPercent: 40, periodMinutes: 300, resetsAt: nil),
                    weekly: UsageMetric(label: "weekly", percentText: "35%", usedPercent: 35, periodMinutes: 10_080, resetsAt: nil),
                    credits: "unlimited"
                ),
                source: "cached 30s",
                usageError: nil
            ),
            AccountUsage(
                name: "beta",
                isCurrent: false,
                hasAuth: true,
                lastUsedAt: nil,
                lastLoginStatus: nil,
                usage: UsageSummary(
                    fiveHour: UsageMetric(label: "5h", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil),
                    weekly: UsageMetric(label: "weekly", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil),
                    credits: "-"
                ),
                source: "-",
                usageError: nil
            ),
        ]

        viewModel.refreshLive()

        await waitUntil(timeoutSeconds: 1.0) {
            service.switchCalls.contains("beta")
        }

        XCTAssertEqual(service.switchCalls.last, "beta")
    }

    func testSendTestAutoSwitchNotificationUsesCurrentAndNextAccount() {
        let defaults = ephemeralDefaults()
        var preferences = AppPreferencesStore(defaults: defaults)
        preferences.autoSwitchNotificationsEnabled = true

        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
            AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 25, weeklyUsed: 35), ageSec: nil),
                LimitsResult(account: "beta", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 15, weeklyUsed: 20), ageSec: nil),
            ],
            errors: []
        )

        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: preferences,
            startImmediately: false
        )
        viewModel.accounts = AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
            limits: service.stubbedLimits
        )

        viewModel.sendTestAutoSwitchNotification()

        XCTAssertEqual(viewModel.accountActionMessage, "Sent test notification alpha -> beta.")
        XCTAssertEqual(notifier.authorizationRequests, 1)
        XCTAssertEqual(
            notifier.sentPayloads,
            [
                AutoSwitchNotificationPayload(
                    previousAccountName: "alpha",
                    newAccountName: "beta",
                    reason: "5h window expiring"
                ),
            ]
        )
    }

    func testSetAccountSwitchingStrategyTriggersImmediateLiveRefreshForAutomaticModes() async {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.setAccountSwitchingStrategy(.failover)

        await waitUntil(timeoutSeconds: 1.0) {
            service.fetchLimitsRefreshLiveCalls.contains(true)
        }

        XCTAssertTrue(service.fetchLimitsRefreshLiveCalls.contains(true))
    }

    func testExpiryAwareStrategyAutomaticallySwitchesToSoonerExpiringHeadroom() async {
        let defaults = ephemeralDefaults()
        var preferences = AppPreferencesStore(defaults: defaults)
        preferences.accountSwitchingStrategy = .expiryAware
        preferences.autoSwitchNotificationsEnabled = true

        let now = Date()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
            AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(
                    account: "alpha",
                    source: "live-api",
                    snapshot: makeSnapshot(
                        fiveHourUsed: 55,
                        fiveHourReset: now.addingTimeInterval(4 * 3_600),
                        weeklyUsed: 45,
                        weeklyReset: now.addingTimeInterval(6 * 24 * 3_600)
                    ),
                    ageSec: nil
                ),
                LimitsResult(
                    account: "beta",
                    source: "live-api",
                    snapshot: makeSnapshot(
                        fiveHourUsed: 15,
                        fiveHourReset: now.addingTimeInterval(30 * 60),
                        weeklyUsed: 35,
                        weeklyReset: now.addingTimeInterval(4 * 24 * 3_600)
                    ),
                    ageSec: nil
                ),
                ],
            errors: []
        )

        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: preferences,
            startImmediately: false
        )

        viewModel.refreshLive()

        await waitUntil(timeoutSeconds: 1.0) {
            service.switchCalls.contains("beta")
        }

        XCTAssertEqual(service.switchCalls.last, "beta")
        XCTAssertEqual(viewModel.accountActionMessage, "Auto-switched alpha -> beta. 5h window expiring.")
        XCTAssertEqual(
            notifier.sentPayloads,
            [
                AutoSwitchNotificationPayload(
                    previousAccountName: "alpha",
                    newAccountName: "beta",
                    reason: "5h window expiring"
                ),
            ]
        )
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
        viewModel.accounts = AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
            limits: service.stubbedLimits
        )

        viewModel.openLoginInTerminal(for: "alpha")

        await waitUntil(timeoutSeconds: 1.0) {
            service.openLoginCalls.contains("alpha")
        }

        XCTAssertEqual(service.openLoginCalls, ["alpha"])
        XCTAssertTrue((viewModel.accountActionMessage ?? "").contains("Terminal fallback"))

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        await waitUntil(timeoutSeconds: 1.0) {
            service.importFromHomeCalls.contains(where: { $0.name == "alpha" })
                && service.statusForLoginHomeCalls.contains("alpha")
        }

        XCTAssertTrue(service.importFromHomeCalls.contains(where: { $0.name == "alpha" }))
        XCTAssertTrue(service.statusForLoginHomeCalls.contains("alpha"))
        XCTAssertTrue(service.switchCalls.contains("alpha"))
    }

    func testStartLoginFlowKeepsRetryableSessionWhenTerminalLoginFails() async {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.loginInAppError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "stdin not interactive"])
        service.loginHomeStatusExitCode = 1
        service.loginHomeStatusOutput = "authorization failed"

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

        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        await waitUntil(timeoutSeconds: 1.0) {
            (viewModel.accountActionError ?? "").contains("authorization failed")
        }

        XCTAssertEqual(viewModel.pendingInteractiveLoginSession?.phase, .needsRetry)
        XCTAssertTrue(service.importFromHomeCalls.isEmpty)
    }

    func testStartNewAccountLoginStoresAuthWithoutAutoSwitching() async {
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

        viewModel.startLoginFlow(accountName: "fresh", createIfNeeded: true)

        await waitUntil(timeoutSeconds: 1.0) {
            service.importFromHomeCalls.contains(where: { $0.name == "fresh" })
        }

        XCTAssertTrue(service.switchCalls.isEmpty)
    }

    func testSwitchToAccountCompletesBeforeBackgroundRefreshFinishes() async throws {
        let defaults = ephemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
            AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: nil, ageSec: nil),
                LimitsResult(account: "beta", source: "live-api", snapshot: nil, ageSec: nil),
            ],
            errors: []
        )

        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        viewModel.accounts = AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
            limits: service.stubbedLimits
        )
        service.fetchLimitsDelayNanoseconds = 400_000_000

        viewModel.switchToAccount(named: "beta")

        await waitUntil(timeoutSeconds: 1.0) {
            service.switchCalls.contains("beta")
        }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.switchingAccountName)
        XCTAssertEqual(viewModel.currentAccount?.name, "beta")
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

    private func makeSnapshot(
        fiveHourUsed: Double,
        fiveHourReset: Date? = nil,
        weeklyUsed: Double,
        weeklyReset: Date? = nil
    ) -> RateLimitSnapshot {
        RateLimitSnapshot(
            primary: RateLimitWindow(
                usedPercent: fiveHourUsed,
                windowDurationMins: 300,
                resetsAt: fiveHourReset?.timeIntervalSince1970
            ),
            secondary: RateLimitWindow(
                usedPercent: weeklyUsed,
                windowDurationMins: 10_080,
                resetsAt: weeklyReset?.timeIntervalSince1970
            ),
            credits: nil
        )
    }
}

private final class MockCodexAccountService: CodexAccountServicing {
    struct LoginCall {
        let account: String
        let createIfNeeded: Bool
        let loginHome: String?
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
    var fetchLimitsDelayNanoseconds: UInt64 = 0
    var loginHomeStatusError: Error?
    var loginHomeStatusExitCode = 0
    var loginHomeStatusOutput = "ok"
    var probeRuntimeResult = CodexAccountService.RuntimeProbe(isAvailable: true, summary: "ok")

    private(set) var switchCalls: [String] = []
    private(set) var removeCalls: [RemoveCall] = []
    private(set) var renameCalls: [(from: String, to: String)] = []
    private(set) var importCalls: [String] = []
    private(set) var statusCalls: [String] = []
    private(set) var importFromHomeCalls: [(home: String, name: String)] = []
    private(set) var statusForLoginHomeCalls: [String] = []
    private(set) var openLoginCalls: [String] = []
    private(set) var openNewLoginCalls: [String] = []
    private(set) var loginInAppCalls: [LoginCall] = []
    private(set) var fetchLimitsRefreshLiveCalls: [Bool] = []

    func fetchAccounts() async throws -> AccountsListPayload {
        if let fetchAccountsError {
            throw fetchAccountsError
        }
        let current = stubbedAccounts.first(where: { $0.isCurrent })?.name
        return AccountsListPayload(accounts: stubbedAccounts, currentAccount: current)
    }

    func fetchLimits(refreshLive: Bool) async throws -> LimitsPayload {
        if let fetchLimitsError {
            throw fetchLimitsError
        }
        fetchLimitsRefreshLiveCalls.append(refreshLive)
        if fetchLimitsDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: fetchLimitsDelayNanoseconds)
        }
        return stubbedLimits
    }

    func switchAccount(name: String) async throws {
        if let switchError {
            throw switchError
        }
        switchCalls.append(name)
        stubbedAccounts = stubbedAccounts.map { account in
            AccountEntry(
                name: account.name,
                isCurrent: account.name == name,
                hasAuth: account.hasAuth,
                lastUsedAt: account.lastUsedAt,
                lastLoginStatus: account.lastLoginStatus
            )
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

    func importAuth(fromHome homePath: String, into name: String) async throws -> ImportAccountPayload {
        if let importError {
            throw importError
        }
        importFromHomeCalls.append((home: homePath, name: name))
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

    func fetchStatusForLoginHome(_ homePath: String, accountName: String) async throws -> AccountStatusPayload {
        if let loginHomeStatusError {
            throw loginHomeStatusError
        }
        statusForLoginHomeCalls.append(accountName)
        return AccountStatusPayload(
            account: accountName,
            exitCode: loginHomeStatusExitCode,
            stdout: "",
            stderr: "",
            output: loginHomeStatusOutput,
            checkedAt: homePath
        )
    }

    func openLoginInTerminal(account name: String, loginHome _: String?) throws {
        if let openLoginError {
            throw openLoginError
        }
        openLoginCalls.append(name)
    }

    func openNewAccountLoginInTerminal(newAccountName name: String, loginHome _: String?) throws {
        if let openNewLoginError {
            throw openNewLoginError
        }
        openNewLoginCalls.append(name)
    }

    func loginInApp(account name: String, createIfNeeded: Bool, loginHome: String?) async throws -> String {
        loginInAppCalls.append(LoginCall(account: name, createIfNeeded: createIfNeeded, loginHome: loginHome))
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

private final class MockAutoSwitchNotifier: AutoSwitchNotificationSending {
    private(set) var authorizationRequests = 0
    private(set) var sentPayloads: [AutoSwitchNotificationPayload] = []

    func requestAuthorizationIfNeeded() {
        authorizationRequests += 1
    }

    func send(_ payload: AutoSwitchNotificationPayload) {
        sentPayloads.append(payload)
    }
}
