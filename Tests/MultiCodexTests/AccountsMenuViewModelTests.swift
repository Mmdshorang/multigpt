import AppKit
import XCTest
@testable import MultiCodex

@MainActor
final class AccountsMenuViewModelTests: XCTestCase {
    func testSetLimitsCacheTTLUpdatesServiceAndPreferences() {
        let defaults = makeEphemeralDefaults()
        let preferences = AppPreferencesStore(defaults: defaults)
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
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
        let defaults = makeEphemeralDefaults()
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
        // Authorization is requested when notifications are explicitly enabled.
        XCTAssertEqual(notifier.authorizationRequests, 1)
        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.accountSwitchingStrategy, .expiryAware)
        XCTAssertTrue(persisted.autoSwitchNotificationsEnabled)
    }

    func testSelectSettingsSectionPersistsSelection() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.selectSettingsSection(.accounts)

        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.selectedSettingsSection, .accounts)
    }

    func testResetOnboardingWizardReturnsToGeneralAndClearsSelectedAccount() {
        let defaults = makeEphemeralDefaults()
        defaults.set("beta", forKey: AppPreferencesStore.Keys.selectedSettingsAccountName)
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.selectSettingsSection(.accounts)
        viewModel.resetOnboardingWizard()

        XCTAssertEqual(viewModel.selectedSettingsSection, .general)
        XCTAssertNil(viewModel.selectedSettingsAccountName)
        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.selectedSettingsSection, .general)
        XCTAssertNil(persisted.selectedSettingsAccountName)
    }

    func testUpdateCustomCodexPathUpdatesServiceAndStore() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.updateCustomCodexPath(" /usr/local/bin/codex ")

        XCTAssertEqual(service.customCodexPath, "/usr/local/bin/codex")
        let persisted = AppPreferencesStore(defaults: defaults)
        XCTAssertEqual(persisted.customCodexPath, "/usr/local/bin/codex")
    }

    func testMenuAccountRowsExcludeCurrentAccount() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
                accounts: AccountsListPayload(
                    accounts: [
                        AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
                        AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
                        AccountEntry(name: "gamma", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
                    ],
                    currentAccount: "alpha"
                ),
                limits: LimitsPayload(results: [], errors: [])
            )
        )

        let rows = viewModel.menuAccountRows(limit: 5)

        XCTAssertEqual(rows.map(\.name), ["beta", "gamma"])
    }

    func testUsageModeChangesBothProgressAndPercentText() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        let metric = UsageMetric(label: "5h", percentText: "72.4%", usedPercent: 72.4, periodMinutes: 300, resetsAt: nil)

        viewModel.setUsageBarStyle(.filling)
        XCTAssertEqual(viewModel.progressValue(for: metric), 0.724, accuracy: 0.000_1)
        XCTAssertEqual(viewModel.displayPercentText(for: metric), "72.4%")

        viewModel.setUsageBarStyle(.depleting)
        XCTAssertEqual(viewModel.progressValue(for: metric), 0.276, accuracy: 0.000_1)
        XCTAssertEqual(viewModel.displayPercentText(for: metric), "27.6%")
    }

    func testCompactIndicatorUsesMostConstrainedWindowInBothModes() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        let usage = UsageSummary(
            fiveHour: UsageMetric(label: "5h", percentText: "92%", usedPercent: 92, periodMinutes: 300, resetsAt: nil),
            weekly: UsageMetric(label: "weekly", percentText: "10%", usedPercent: 10, periodMinutes: 10_080, resetsAt: nil),
            credits: "unlimited"
        )

        viewModel.setUsageBarStyle(.filling)
        XCTAssertEqual(viewModel.compactUsedPercent(for: usage) ?? -1, 92, accuracy: 0.000_1)
        XCTAssertEqual(viewModel.compactProgressValue(for: usage), 0.92, accuracy: 0.000_1)
        XCTAssertEqual(viewModel.compactPercentText(for: usage), "92%")

        viewModel.setUsageBarStyle(.depleting)
        XCTAssertEqual(viewModel.compactUsedPercent(for: usage) ?? -1, 92, accuracy: 0.000_1)
        XCTAssertEqual(viewModel.compactProgressValue(for: usage), 0.08, accuracy: 0.000_1)
        XCTAssertEqual(viewModel.compactPercentText(for: usage), "8%")
    }

    func testMenuBarUsesMostConstrainedWindowForTitleAndSymbol() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
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
                    fiveHour: UsageMetric(label: "5h", percentText: "10%", usedPercent: 10, periodMinutes: 300, resetsAt: nil),
                    weekly: UsageMetric(label: "weekly", percentText: "90%", usedPercent: 90, periodMinutes: 10_080, resetsAt: nil),
                    credits: "unlimited"
                ),
                source: "live-api",
                usageError: nil
            ),
        ]

        viewModel.setUsageBarStyle(.filling)
        XCTAssertEqual(viewModel.menuBarTitle, "mcx 90%")
        XCTAssertEqual(viewModel.menuBarSymbol, "gauge.with.dots.needle.67percent")

        viewModel.setUsageBarStyle(.depleting)
        XCTAssertEqual(viewModel.menuBarTitle, "mcx 10%")
        XCTAssertEqual(viewModel.menuBarSymbol, "gauge.with.dots.needle.67percent")
    }

    func testDefaultSortValuesLoadFromFreshPreferences() {
        let viewModel = makeSortViewModel()

        XCTAssertEqual(viewModel.accountSortCriterion, .used)
        XCTAssertEqual(viewModel.accountSortWindow, .fiveHour)
        XCTAssertEqual(viewModel.accountSortDirection, .descending)
    }

    func testCurrentAccountRemainsPinnedFirstAcrossSortCriteria() {
        let viewModel = makeSortViewModel()
        viewModel.updateAccounts(
            [
                makeSortAccount("beta", fiveHourUsed: 20, weeklyUsed: 40),
                makeSortAccount("alpha", isCurrent: true, fiveHourUsed: 55, weeklyUsed: 35),
                makeSortAccount("gamma", fiveHourUsed: 80, weeklyUsed: 70),
            ]
        )

        for criterion in AccountSortCriterion.allCases {
            viewModel.setAccountSortCriterion(criterion)
            if criterion != .name {
                viewModel.setAccountSortWindow(.weekly)
            }
            viewModel.setAccountSortDirection(.ascending)

            XCTAssertEqual(viewModel.currentAccount?.name, "alpha")
            XCTAssertEqual(viewModel.accounts.first?.name, "alpha")
        }
    }

    func testUsedSortByWindowHonorsDirectionAndMissingUsageAtBottom() {
        let viewModel = makeSortViewModel()
        viewModel.updateAccounts(
            [
                makeSortAccount("alpha", isCurrent: true, fiveHourUsed: 50, weeklyUsed: 50),
                makeSortAccount("beta", fiveHourUsed: 20, weeklyUsed: 90),
                makeSortAccount("gamma", fiveHourUsed: 80, weeklyUsed: 30),
                makeSortAccount("delta", fiveHourUsed: 50, weeklyUsed: 60),
                makeSortAccount("epsilon", fiveHourUsed: nil, weeklyUsed: nil),
            ]
        )

        viewModel.setAccountSortCriterion(.used)
        viewModel.setAccountSortWindow(.fiveHour)
        viewModel.setAccountSortDirection(.ascending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "beta", "delta", "gamma", "epsilon"])

        viewModel.setAccountSortDirection(.descending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "gamma", "delta", "beta", "epsilon"])

        viewModel.setAccountSortWindow(.weekly)
        viewModel.setAccountSortDirection(.ascending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "gamma", "delta", "beta", "epsilon"])

        viewModel.setAccountSortDirection(.descending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "beta", "delta", "gamma", "epsilon"])
    }

    func testRemainingSortByWindowHonorsDirection() {
        let viewModel = makeSortViewModel()
        viewModel.updateAccounts(
            [
                makeSortAccount("alpha", isCurrent: true, fiveHourUsed: 50, weeklyUsed: 50),
                makeSortAccount("beta", fiveHourUsed: 20, weeklyUsed: 90),
                makeSortAccount("gamma", fiveHourUsed: 80, weeklyUsed: 30),
                makeSortAccount("delta", fiveHourUsed: 50, weeklyUsed: 60),
            ]
        )

        viewModel.setAccountSortCriterion(.remaining)
        viewModel.setAccountSortWindow(.fiveHour)
        viewModel.setAccountSortDirection(.ascending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "gamma", "delta", "beta"])

        viewModel.setAccountSortDirection(.descending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "beta", "delta", "gamma"])

        viewModel.setAccountSortWindow(.weekly)
        viewModel.setAccountSortDirection(.ascending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "beta", "delta", "gamma"])

        viewModel.setAccountSortDirection(.descending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "gamma", "delta", "beta"])
    }

    func testNameSortHonorsDirection() {
        let viewModel = makeSortViewModel()
        viewModel.updateAccounts(
            [
                makeSortAccount("delta", fiveHourUsed: 40, weeklyUsed: 40),
                makeSortAccount("alpha", isCurrent: true, fiveHourUsed: 60, weeklyUsed: 60),
                makeSortAccount("charlie", fiveHourUsed: 20, weeklyUsed: 20),
                makeSortAccount("bravo", fiveHourUsed: 80, weeklyUsed: 80),
            ]
        )

        viewModel.setAccountSortCriterion(.name)
        viewModel.setAccountSortDirection(.ascending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "bravo", "charlie", "delta"])

        viewModel.setAccountSortDirection(.descending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "delta", "charlie", "bravo"])
    }

    func testMissingUsageAlwaysStaysAtBottomEvenWhenDescending() {
        let viewModel = makeSortViewModel()
        viewModel.updateAccounts(
            [
                makeSortAccount("alpha", isCurrent: true, fiveHourUsed: 25, weeklyUsed: 25),
                makeSortAccount("beta", fiveHourUsed: nil, weeklyUsed: nil),
                makeSortAccount("gamma", fiveHourUsed: 90, weeklyUsed: 90),
                makeSortAccount("delta", fiveHourUsed: 10, weeklyUsed: 10),
            ]
        )

        viewModel.setAccountSortCriterion(.used)
        viewModel.setAccountSortWindow(.fiveHour)
        viewModel.setAccountSortDirection(.descending)

        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "gamma", "delta", "beta"])
    }

    func testTiesFallBackToNameAscending() {
        let viewModel = makeSortViewModel()
        viewModel.updateAccounts(
            [
                makeSortAccount("alpha", isCurrent: true, fiveHourUsed: 55, weeklyUsed: 55),
                makeSortAccount("zulu", fiveHourUsed: 50, weeklyUsed: 50),
                makeSortAccount("bravo", fiveHourUsed: 50, weeklyUsed: 50),
                makeSortAccount("charlie", fiveHourUsed: 70, weeklyUsed: 70),
            ]
        )

        viewModel.setAccountSortCriterion(.used)
        viewModel.setAccountSortWindow(.fiveHour)
        viewModel.setAccountSortDirection(.ascending)

        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "bravo", "zulu", "charlie"])

        viewModel.setAccountSortDirection(.descending)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "charlie", "bravo", "zulu"])
    }

    func testSortChangesUpdateMenuAndSettingsSourcesImmediatelyAndSettingsDoNotPinCurrentAccount() {
        let viewModel = makeSortViewModel()
        viewModel.updateAccounts(
            [
                makeSortAccount("alpha", isCurrent: true, fiveHourUsed: 80, weeklyUsed: 80),
                makeSortAccount("beta", fiveHourUsed: 30, weeklyUsed: 70),
                makeSortAccount("gamma", fiveHourUsed: 60, weeklyUsed: 20),
                makeSortAccount("delta", fiveHourUsed: 50, weeklyUsed: 50),
            ]
        )

        viewModel.setAccountSortCriterion(.name)
        viewModel.setAccountSortDirection(.descending)

        // Intentionally divergent behavior:
        // - menu rows exclude current account
        // - settings filtered list includes current account and sorts it with others (not pinned)
        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "gamma", "delta", "beta"])
        XCTAssertEqual(viewModel.menuAccountRows(limit: 10).map(\.name), ["gamma", "delta", "beta"])
        XCTAssertEqual(viewModel.filteredAccounts.map(\.name), ["gamma", "delta", "beta", "alpha"])
    }

    func testPerformRefreshHandlesFirstFailureThenWarningFallback() async {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.fetchAccountsError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "accounts unavailable"])
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
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
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [LimitsResult(account: "alpha", source: "live-api", snapshot: nil, ageSec: nil)],
            errors: []
        )
        service.fetchLimitsDelayNanoseconds = 400_000_000

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.refresh()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha"])
        XCTAssertTrue(viewModel.isRefreshing)

        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.isRefreshing
        }
    }

    func testManualStrategyDoesNotAutoSwitch() async {
        let defaults = makeEphemeralDefaults()
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

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
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
        let defaults = makeEphemeralDefaults()
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
        let defaults = makeEphemeralDefaults()
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

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
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
        let defaults = makeEphemeralDefaults()
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
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
                accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
                limits: service.stubbedLimits
            )
        )

        viewModel.sendTestAutoSwitchNotification()

        XCTAssertEqual(
            viewModel.accountActionMessage,
            AutoSwitchNotificationText.sentTestMessage(previousAccountName: "alpha", newAccountName: "beta")
        )
        XCTAssertEqual(notifier.authorizationRequests, 0)
        XCTAssertEqual(
            notifier.sentPayloads,
            [
                AutoSwitchNotificationPayload(
                    previousAccountName: "alpha",
                    newAccountName: "beta",
                    reason: AutoSwitchNotificationText.testReason
                ),
            ]
        )
    }

    func testSendTestAutoSwitchNotificationReportsPermissionDenied() {
        let defaults = makeEphemeralDefaults()
        var preferences = AppPreferencesStore(defaults: defaults)
        preferences.autoSwitchNotificationsEnabled = true

        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        notifier.sendResult = .permissionDenied
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

        XCTAssertNil(viewModel.accountActionMessage)
        XCTAssertEqual(
            viewModel.accountActionError,
            AutoSwitchNotificationText.permissionDenied
        )
    }

    func testEnableAutoSwitchNotificationsReportsPermissionDenied() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        notifier.authorizationGranted = false
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.setAutoSwitchNotificationsEnabled(true)

        XCTAssertEqual(notifier.authorizationRequests, 1)
        XCTAssertEqual(
            viewModel.accountActionError,
            AutoSwitchNotificationText.permissionNotGrantedInSettings
        )
    }

    func testSetAccountSwitchingStrategyTriggersImmediateLiveRefreshForAutomaticModes() async {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
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
        let defaults = makeEphemeralDefaults()
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
                    reason: AutoSwitchNotificationText.testReason
                ),
            ]
        )
    }

    func testStartLoginFlowFallsBackToTerminalAndRecoversOnAppActive() async {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.loginInAppError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "stdin not interactive"])

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
                limits: service.stubbedLimits
            )
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
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.loginInAppError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "stdin not interactive"])
        service.loginHomeStatusExitCode = 1
        service.loginHomeStatusOutput = "authorization failed"

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
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
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.startLoginFlow(accountName: "fresh", createIfNeeded: true)

        await waitUntil(timeoutSeconds: 1.0) {
            service.importFromHomeCalls.contains(where: { $0.name == "fresh" })
        }

        XCTAssertTrue(service.switchCalls.isEmpty)
    }

    func testStartNewAccountLoginAutoRenamesToDefaultWorkspaceEmail() async {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedInferredEmailFromLoginHome = "personal-fresh@example.com"

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.startLoginFlow(accountName: "fresh", createIfNeeded: true)

        await waitUntil(timeoutSeconds: 1.0) {
            service.renameCalls.contains(where: { $0.from == "fresh" && $0.to == "personal-fresh@example.com" })
        }

        XCTAssertTrue(viewModel.accounts.contains(where: { $0.name == "personal-fresh@example.com" && $0.hasAuth }))
    }

    func testStartLoginFlowUsesPersistentLoginSandboxHomePath() async {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.startLoginFlow(accountName: "fresh", createIfNeeded: true)

        await waitUntil(timeoutSeconds: 1.0) {
            !service.loginInAppCalls.isEmpty
        }

        let loginHome = service.loginInAppCalls.first?.loginHome
        XCTAssertNotNil(loginHome)
        XCTAssertTrue(loginHome?.contains("/.multicodex/login-sandboxes/session-") == true)
        XCTAssertFalse(loginHome?.contains("/T/multicodex-login-") == true)
    }

    func testStartLoginFlowCleansUpPersistentLoginSandboxAfterCompletion() async {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.startLoginFlow(accountName: "fresh", createIfNeeded: true)

        await waitUntil(timeoutSeconds: 1.0) {
            !service.loginInAppCalls.isEmpty && service.importFromHomeCalls.contains(where: { $0.name == "fresh" })
        }

        let loginHome = service.loginInAppCalls.first?.loginHome
        XCTAssertNotNil(loginHome)
        if let loginHome {
            await waitUntil(timeoutSeconds: 1.0) {
                !FileManager.default.fileExists(atPath: loginHome)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: loginHome))
        }
    }

    func testPrepareSequentialNewAccountLoginClampsRequestedCountToFive() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.prepareSequentialNewAccountLogin(count: 99)

        XCTAssertEqual(viewModel.sequentialLoginState?.totalCount, SequentialLoginState.maxAccountCount)
        XCTAssertEqual(viewModel.sequentialLoginState?.pendingCount, SequentialLoginState.maxAccountCount)
    }

    func testSequentialNewAccountLoginContinuesOnFailureAndRetriesFailedOnly() async {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.prepareSequentialNewAccountLogin(count: 3)
        let preparedNames = viewModel.sequentialLoginState?.items.map(\.accountName) ?? []
        XCTAssertEqual(preparedNames.count, 3)
        service.loginInAppErrorByAccount[preparedNames[1]] = NSError(
            domain: "test",
            code: 99,
            userInfo: [NSLocalizedDescriptionKey: "simulated failure"]
        )

        viewModel.startSequentialNewAccountLogin()

        await waitUntil(timeoutSeconds: 1.5) {
            viewModel.sequentialLoginState?.isFinished == true
        }

        XCTAssertEqual(viewModel.sequentialLoginState?.successCount, 2)
        XCTAssertEqual(viewModel.sequentialLoginState?.failedCount, 1)
        XCTAssertTrue(service.removeCalls.contains(where: { $0.name == preparedNames[1] && $0.deleteData }))

        service.loginInAppErrorByAccount[preparedNames[1]] = nil
        viewModel.retryFailedSequentialNewAccountLogin()

        await waitUntil(timeoutSeconds: 1.5) {
            viewModel.sequentialLoginState?.isFinished == true
                && viewModel.sequentialLoginState?.totalCount == 1
        }

        XCTAssertEqual(viewModel.sequentialLoginState?.successCount, 1)
        XCTAssertEqual(viewModel.sequentialLoginState?.failedCount, 0)
    }

    func testStartSequentialNewAccountLoginDoesNotStartWhileSwitchIsInProgress() {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.prepareSequentialNewAccountLogin(count: 2)
        viewModel.switchingAccountName = "alpha"
        viewModel.startSequentialNewAccountLogin()

        XCTAssertEqual(viewModel.sequentialLoginState?.isRunning, false)
        XCTAssertNil(viewModel.sequentialLoginTask)
    }

    func testCancelSequentialNewAccountLoginMarksRemainingAsCancelledAndCleansUp() async {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.loginInAppDelayNanoseconds = 300_000_000

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )

        viewModel.prepareSequentialNewAccountLogin(count: 3)
        let preparedNames = viewModel.sequentialLoginState?.items.map(\.accountName) ?? []
        XCTAssertEqual(preparedNames.count, 3)

        viewModel.startSequentialNewAccountLogin()
        viewModel.cancelSequentialNewAccountLogin()

        await waitUntil(timeoutSeconds: 2.0) {
            viewModel.sequentialLoginState?.isFinished == true
        }

        let cancelledOrFailed = Set(
            viewModel.sequentialLoginState?.items
                .filter { $0.status == .cancelled || $0.status == .failed }
                .map(\.accountName) ?? []
        )
        XCTAssertFalse(cancelledOrFailed.isEmpty)
        XCTAssertTrue(
            service.removeCalls.contains(where: { call in
                cancelledOrFailed.contains(call.name) && call.deleteData
            })
        )
    }

    func testSwitchToAccountCompletesBeforeBackgroundRefreshFinishes() async throws {
        let defaults = makeEphemeralDefaults()
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

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
                limits: service.stubbedLimits
            )
        )
        service.fetchLimitsDelayNanoseconds = 400_000_000

        viewModel.switchToAccount(named: "beta")

        await waitUntil(timeoutSeconds: 1.0) {
            service.switchCalls.contains("beta")
        }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(viewModel.switchingAccountName)
        XCTAssertEqual(viewModel.currentAccount?.name, "beta")

        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.isRefreshing
        }
    }

    func testRenameAccountUpdatesLocalStateBeforeBackgroundRefreshFinishes() async throws {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
            AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 10, weeklyUsed: 20), ageSec: nil),
                LimitsResult(account: "beta", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 30, weeklyUsed: 40), ageSec: nil),
            ],
            errors: []
        )

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
                limits: service.stubbedLimits
            )
        )
        viewModel.focusedAccountName = "beta"
        service.fetchLimitsDelayNanoseconds = 400_000_000

        viewModel.renameAccount(from: "beta", to: "gamma")

        await waitUntil(timeoutSeconds: 1.0) {
            service.renameCalls.contains(where: { $0.from == "beta" && $0.to == "gamma" })
        }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha", "gamma"])
        XCTAssertEqual(viewModel.focusedAccountName, "gamma")
        XCTAssertEqual(
            viewModel.accounts.first(where: { $0.name == "gamma" })?.usage.fiveHour.percentText,
            "30%"
        )

        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.isRefreshing && viewModel.accountActionInFlightName == nil
        }

        viewModel.clearAccountActionFeedback()
    }

    func testRemoveAccountUpdatesLocalStateBeforeBackgroundRefreshFinishes() async throws {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
            AccountEntry(name: "beta", isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 10, weeklyUsed: 20), ageSec: nil),
                LimitsResult(account: "beta", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 30, weeklyUsed: 40), ageSec: nil),
            ],
            errors: []
        )

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
                limits: service.stubbedLimits
            )
        )
        service.fetchLimitsDelayNanoseconds = 400_000_000

        viewModel.removeAccount(named: "beta", deleteData: false)

        await waitUntil(timeoutSeconds: 1.0) {
            service.removeCalls.contains(where: { $0.name == "beta" })
        }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.accounts.map(\.name), ["alpha"])
        XCTAssertNil(viewModel.accountActionInFlightName)

        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.isRefreshing
        }
    }

    func testImportAuthUpdatesLocalStateBeforeBackgroundRefreshFinishes() async throws {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: false, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 10, weeklyUsed: 20), ageSec: nil),
            ],
            errors: []
        )

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
                limits: service.stubbedLimits
            )
        )
        service.fetchLimitsDelayNanoseconds = 400_000_000

        viewModel.importCurrentAuth(into: "alpha")

        await waitUntil(timeoutSeconds: 1.0) {
            service.importCalls.contains("alpha")
        }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.accounts.first?.hasAuth, true)
        XCTAssertNil(viewModel.accountActionInFlightName)

        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.isRefreshing
        }
    }

    func testCheckStatusUpdatesLocalStateBeforeBackgroundRefreshFinishes() async throws {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 10, weeklyUsed: 20), ageSec: nil),
            ],
            errors: []
        )

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
            accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
                limits: service.stubbedLimits
            )
        )
        service.fetchLimitsDelayNanoseconds = 400_000_000

        viewModel.checkLoginStatus(for: "alpha")

        await waitUntil(timeoutSeconds: 1.0) {
            service.statusCalls.contains("alpha")
        }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.accounts.first?.lastLoginStatus, "ok")
        XCTAssertNil(viewModel.accountActionInFlightName)

        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.isRefreshing
        }
    }

    func testStartNewAccountLoginUpdatesLocalStateBeforeBackgroundRefreshFinishes() async throws {
        let defaults = makeEphemeralDefaults()
        let service = MockCodexAccountService()
        service.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        service.stubbedLimits = LimitsPayload(
            results: [
                LimitsResult(account: "alpha", source: "live-api", snapshot: makeSnapshot(fiveHourUsed: 10, weeklyUsed: 20), ageSec: nil),
            ],
            errors: []
        )
        service.fetchLimitsDelayNanoseconds = 400_000_000

        let notifier = MockAutoSwitchNotifier()
        let viewModel = AccountsMenuViewModel(
            accountService: service,
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: defaults),
            startImmediately: false
        )
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
                accounts: AccountsListPayload(accounts: service.stubbedAccounts, currentAccount: "alpha"),
                limits: service.stubbedLimits
            )
        )

        viewModel.startLoginFlow(accountName: "fresh", createIfNeeded: true)

        await waitUntil(timeoutSeconds: 1.0) {
            service.importFromHomeCalls.contains(where: { $0.name == "fresh" })
        }
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(viewModel.accounts.contains(where: { $0.name == "fresh" && $0.hasAuth }))
        XCTAssertNil(viewModel.accountActionInFlightName)

        await waitUntil(timeoutSeconds: 1.0) {
            !viewModel.isRefreshing
        }
    }

    func testOnboardingStateTransitionsMatrix() async {
        let runtimeOffService = MockCodexAccountService()
        runtimeOffService.probeRuntimeResult = RuntimeProbe(isAvailable: false, summary: "missing runtime")
        let runtimeOffNotifier = MockAutoSwitchNotifier()
        let runtimeOff = AccountsMenuViewModel(
            accountService: runtimeOffService,
            fileManager: .default,
            autoSwitchNotifier: { runtimeOffNotifier },
            preferences: AppPreferencesStore(defaults: makeEphemeralDefaults()),
            startImmediately: false
        )
        XCTAssertEqual(runtimeOff.onboardingState.step, .runtime)

        let emptyService = MockCodexAccountService()
        emptyService.probeRuntimeResult = RuntimeProbe(isAvailable: true, summary: "ok")
        let emptyNotifier = MockAutoSwitchNotifier()
        let empty = AccountsMenuViewModel(
            accountService: emptyService,
            fileManager: .default,
            autoSwitchNotifier: { emptyNotifier },
            preferences: AppPreferencesStore(defaults: makeEphemeralDefaults()),
            startImmediately: false
        )
        XCTAssertEqual(empty.onboardingState.step, .login)

        let needsLoginService = MockCodexAccountService()
        needsLoginService.stubbedAccounts = [
            AccountEntry(name: "alpha", isCurrent: true, hasAuth: false, lastUsedAt: nil, lastLoginStatus: nil),
        ]
        let needsLoginNotifier = MockAutoSwitchNotifier()
        let needsLogin = AccountsMenuViewModel(
            accountService: needsLoginService,
            fileManager: .default,
            autoSwitchNotifier: { needsLoginNotifier },
            preferences: AppPreferencesStore(defaults: makeEphemeralDefaults()),
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
        let completeNotifier = MockAutoSwitchNotifier()
        let complete = AccountsMenuViewModel(
            accountService: completeService,
            fileManager: .default,
            autoSwitchNotifier: { completeNotifier },
            preferences: AppPreferencesStore(defaults: makeEphemeralDefaults()),
            startImmediately: false
        )
        complete.refresh()
        await waitUntil(timeoutSeconds: 1.0) {
            !complete.accounts.isEmpty
        }
        XCTAssertEqual(complete.onboardingState.step, .done)
    }

    // Note: Uses makeEphemeralDefaults() from TestFixtures.swift

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

    private func makeSortViewModel() -> AccountsMenuViewModel {
        let notifier = MockAutoSwitchNotifier()
        return AccountsMenuViewModel(
            accountService: MockCodexAccountService(),
            fileManager: .default,
            autoSwitchNotifier: { notifier },
            preferences: AppPreferencesStore(defaults: makeEphemeralDefaults()),
            startImmediately: false
        )
    }

    private func makeSortAccount(
        _ name: String,
        isCurrent: Bool = false,
        fiveHourUsed: Double?,
        weeklyUsed: Double?
    ) -> AccountUsage {
        AccountUsage(
            name: name,
            isCurrent: isCurrent,
            hasAuth: true,
            lastUsedAt: nil,
            lastLoginStatus: nil,
            usage: UsageSummary(
                fiveHour: UsageMetric(
                    label: "5h",
                    percentText: percentText(for: fiveHourUsed),
                    usedPercent: fiveHourUsed,
                    periodMinutes: 300,
                    resetsAt: nil
                ),
                weekly: UsageMetric(
                    label: "weekly",
                    percentText: percentText(for: weeklyUsed),
                    usedPercent: weeklyUsed,
                    periodMinutes: 10_080,
                    resetsAt: nil
                ),
                credits: "-"
            ),
            source: "live-api",
            usageError: nil
        )
    }

    private func percentText(for value: Double?) -> String {
        guard let value else {
            return "-"
        }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f%%", value)
        }
        return String(format: "%.1f%%", value)
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
    var loginInAppErrorByAccount: [String: Error] = [:]
    var loginInAppDelayNanoseconds: UInt64 = 0
    var fetchLimitsDelayNanoseconds: UInt64 = 0
    var loginHomeStatusError: Error?
    var loginHomeStatusExitCode = 0
    var loginHomeStatusOutput = "ok"
    var probeRuntimeResult = RuntimeProbe(isAvailable: true, summary: "ok")
    var stubbedDefaultWorkspaceEmailByAccount: [String: String] = [:]
    var stubbedInferredEmailFromLoginHome: String?

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
        let withIdentity = stubbedAccounts.map { account in
            AccountEntry(
                name: account.name,
                isCurrent: account.isCurrent,
                hasAuth: account.hasAuth,
                lastUsedAt: account.lastUsedAt,
                lastLoginStatus: account.lastLoginStatus,
                defaultWorkspaceEmail: stubbedDefaultWorkspaceEmailByAccount[account.name]
            )
        }
        return AccountsListPayload(accounts: withIdentity, currentAccount: current)
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
        let removedWasCurrent = stubbedAccounts.contains(where: { $0.name == name && $0.isCurrent })
        stubbedAccounts.removeAll { $0.name == name }
        if removedWasCurrent {
            let nextCurrent = stubbedAccounts.first?.name
            stubbedAccounts = stubbedAccounts.map { account in
                AccountEntry(
                    name: account.name,
                    isCurrent: account.name == nextCurrent,
                    hasAuth: account.hasAuth,
                    lastUsedAt: account.lastUsedAt,
                    lastLoginStatus: account.lastLoginStatus
                )
            }
            return RemoveAccountPayload(removedAccount: name, currentAccount: nextCurrent)
        }
        return RemoveAccountPayload(
            removedAccount: name,
            currentAccount: stubbedAccounts.first(where: \.isCurrent)?.name
        )
    }

    func renameAccount(from oldName: String, to newName: String) async throws -> RenameAccountPayload {
        if let renameError {
            throw renameError
        }
        renameCalls.append((from: oldName, to: newName))
        if let defaultWorkspaceEmail = stubbedDefaultWorkspaceEmailByAccount.removeValue(forKey: oldName) {
            stubbedDefaultWorkspaceEmailByAccount[newName] = defaultWorkspaceEmail
        }
        stubbedAccounts = stubbedAccounts.map { account in
            let effectiveName = account.name == oldName ? newName : account.name
            return AccountEntry(
                name: effectiveName,
                isCurrent: account.isCurrent,
                hasAuth: account.hasAuth,
                lastUsedAt: account.lastUsedAt,
                lastLoginStatus: account.lastLoginStatus
            )
        }
        return RenameAccountPayload(from: oldName, to: newName, currentAccount: nil)
    }

    func importDefaultAuth(into name: String) async throws -> ImportAccountPayload {
        if let importError {
            throw importError
        }
        importCalls.append(name)
        stubbedAccounts = stubbedAccounts.map { account in
            guard account.name == name else { return account }
            return AccountEntry(
                name: account.name,
                isCurrent: account.isCurrent,
                hasAuth: true,
                lastUsedAt: account.lastUsedAt,
                lastLoginStatus: account.lastLoginStatus
            )
        }
        return ImportAccountPayload(account: name)
    }

    func importAuth(fromHome homePath: String, into name: String) async throws -> ImportAccountPayload {
        if let importError {
            throw importError
        }
        importFromHomeCalls.append((home: homePath, name: name))
        if stubbedAccounts.contains(where: { $0.name == name }) {
            stubbedAccounts = stubbedAccounts.map { account in
                guard account.name == name else { return account }
                return AccountEntry(
                    name: account.name,
                    isCurrent: account.isCurrent,
                    hasAuth: true,
                    lastUsedAt: account.lastUsedAt,
                    lastLoginStatus: account.lastLoginStatus
                )
            }
        } else {
            stubbedAccounts.append(
                AccountEntry(name: name, isCurrent: false, hasAuth: true, lastUsedAt: nil, lastLoginStatus: nil)
            )
        }
        return ImportAccountPayload(account: name)
    }

    func fetchStatus(name: String) async throws -> AccountStatusPayload {
        if let fetchStatusError {
            throw fetchStatusError
        }
        statusCalls.append(name)
        stubbedAccounts = stubbedAccounts.map { account in
            guard account.name == name else { return account }
            return AccountEntry(
                name: account.name,
                isCurrent: account.isCurrent,
                hasAuth: true,
                lastUsedAt: account.lastUsedAt,
                lastLoginStatus: "ok"
            )
        }
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
        if loginInAppDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: loginInAppDelayNanoseconds)
        }
        if let accountSpecificError = loginInAppErrorByAccount[name] {
            throw accountSpecificError
        }
        if let loginInAppError {
            throw loginInAppError
        }
        return "ok"
    }

    func inferDefaultWorkspaceEmail(fromLoginHome _: String) -> String? {
        stubbedInferredEmailFromLoginHome
    }

    func effectiveMulticodexHomePath() -> String {
        "/tmp"
    }

    func probeRuntime() -> RuntimeProbe {
        probeRuntimeResult
    }
}

private final class MockAutoSwitchNotifier: AutoSwitchNotificationSending {
    private(set) var authorizationRequests = 0
    private(set) var sentPayloads: [AutoSwitchNotificationPayload] = []
    var authorizationGranted = true
    var sendResult: AutoSwitchNotificationSendResult = .delivered

    func requestAuthorizationIfNeeded() {
        authorizationRequests += 1
    }

    func requestAuthorization(completion: ((Bool) -> Void)?) {
        authorizationRequests += 1
        completion?(authorizationGranted)
    }

    func send(_ payload: AutoSwitchNotificationPayload, completion: ((AutoSwitchNotificationSendResult) -> Void)?) {
        sentPayloads.append(payload)
        completion?(sendResult)
    }
}
