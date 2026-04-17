import AppKit
import Foundation

@MainActor
final class AccountsMenuViewModel: ObservableObject {
    @Published var accounts: [AccountUsage] = []
    @Published var isRefreshing = false
    @Published var lastRefreshError: String?
    @Published var refreshWarningMessage: String?
    @Published var lastUpdatedAt: Date?
    @Published var switchingAccountName: String?
    @Published var cliResolutionHint: String?
    @Published var accountActionInFlightName: String?
    @Published var accountActionMessage: String?
    @Published var accountActionError: String?
    @Published var runtimeProbeSummary: String?
    @Published var isCodexRuntimeAvailable = false
    @Published var focusedAccountName: String?
    @Published var customCodexPath: String
    @Published var resetDisplayMode: ResetDisplayMode
    @Published var selectedSettingsSection: SettingsSection
    @Published var selectedSettingsAccountName: String?
    @Published var accountSearchQuery: String
    @Published var menuDensity: MenuDensity
    @Published var usageBarStyle: UsageBarStyle
    @Published var accountSwitchingStrategy: AccountSwitchingStrategy
    @Published var autoSwitchNotificationsEnabled: Bool
    @Published var limitsCacheTTLSeconds: Int

    let accountService: any CodexAccountServicing
    let fileManager: FileManager
    private let autoSwitchNotifierFactory: () -> any AutoSwitchNotificationSending
    var preferences: AppPreferencesStore

    var refreshLoopTask: Task<Void, Never>?
    var didBecomeActiveObserver: NSObjectProtocol?
    var pendingInteractiveLoginSession: PendingInteractiveLoginSession?
    var feedbackAutoClearTask: Task<Void, Never>?
    lazy var autoSwitchNotifier: any AutoSwitchNotificationSending = autoSwitchNotifierFactory()
    lazy var refreshController = AccountsRefreshController(viewModel: self)
    lazy var accountActions = AccountActionController(viewModel: self)
    lazy var settingsController = AccountsSettingsController(viewModel: self)
    lazy var accountManagement = AccountManagementController(viewModel: self)

    init(
        accountService: any CodexAccountServicing = CodexAccountService(),
        fileManager: FileManager = .default,
        autoSwitchNotifier: @escaping () -> any AutoSwitchNotificationSending = { AutoSwitchNotificationCenter.shared },
        preferences: AppPreferencesStore = AppPreferencesStore(),
        startImmediately: Bool = true
    ) {
        self.accountService = accountService
        self.fileManager = fileManager
        autoSwitchNotifierFactory = autoSwitchNotifier
        self.preferences = preferences

        customCodexPath = preferences.customCodexPath
        resetDisplayMode = preferences.resetDisplayMode
        selectedSettingsSection = preferences.selectedSettingsSection
        selectedSettingsAccountName = preferences.selectedSettingsAccountName
        accountSearchQuery = ""
        menuDensity = preferences.menuDensity
        usageBarStyle = preferences.usageBarStyle
        accountSwitchingStrategy = preferences.accountSwitchingStrategy
        autoSwitchNotificationsEnabled = preferences.autoSwitchNotificationsEnabled
        let persistedTTL = preferences.limitsCacheTTLSeconds
        limitsCacheTTLSeconds = CodexAccountService.normalizedLimitsCacheTTLSeconds(
            persistedTTL > 0 ? persistedTTL : CodexAccountService.defaultLimitsCacheTTLSeconds
        )
        self.accountService.customCodexPath = customCodexPath.isEmpty ? nil : customCodexPath
        self.accountService.limitsCacheTTLSeconds = limitsCacheTTLSeconds
        // Always request notification authorization so the app appears in System Settings
        self.autoSwitchNotifier.requestAuthorization()
        refreshController.refreshRuntimeProbe()
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshController.handleDidBecomeActive()
            }
        }
        if startImmediately {
            start()
        }
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
        feedbackAutoClearTask?.cancel()
        refreshLoopTask?.cancel()
    }

    var currentAccount: AccountUsage? {
        accounts.first(where: { $0.isCurrent })
    }

    var menuBarTitle: String {
        guard let current = currentAccount else {
            return accounts.isEmpty ? "mcx" : "mcx ?"
        }

        if let percent = current.primaryPercentText {
            return "mcx \(percent)"
        }

        return "mcx \(current.name)"
    }

    var menuBarSymbol: String {
        if lastRefreshError != nil {
            return "exclamationmark.triangle.fill"
        }

        switch UsageLevel.from(usedPercent: currentAccount?.usage.fiveHour.usedPercent) {
        case .critical:
            return "flame.fill"
        case .warning:
            return "gauge.with.dots.needle.67percent"
        case .normal:
            return "person.2.circle"
        }
    }

    var currentFiveHourFraction: Double {
        currentAccount?.usage.fiveHour.normalizedFraction ?? 0
    }

    var currentWeeklyFraction: Double {
        currentAccount?.usage.weekly.normalizedFraction ?? 0
    }

    var lastUpdatedLabel: String {
        guard let lastUpdatedAt else {
            return "Not refreshed yet"
        }
        return "Updated \(UsageFormatter.relativeDateFormatter.localizedString(for: lastUpdatedAt, relativeTo: Date()))"
    }

    var accountsNeedingLogin: [AccountUsage] {
        accounts.filter { $0.connectionState == .needsLogin }
    }

    var filteredAccounts: [AccountUsage] {
        let query = accountSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return accounts
        }

        return accounts.filter { account in
            account.name.localizedCaseInsensitiveContains(query)
        }
    }

    var menuListAccounts: [AccountUsage] {
        guard let currentName = currentAccount?.name else {
            return accounts
        }
        return accounts.filter { $0.name != currentName }
    }

    var selectedSettingsAccount: AccountUsage? {
        guard let selectedSettingsAccountName else {
            return nil
        }
        return filteredAccounts.first(where: { $0.name == selectedSettingsAccountName })
            ?? accounts.first(where: { $0.name == selectedSettingsAccountName })
    }

    var onboardingState: OnboardingState {
        if !isCodexRuntimeAvailable {
            return OnboardingState(step: .runtime)
        }
        if accounts.isEmpty {
            return OnboardingState(step: .login)
        }
        if accounts.contains(where: { $0.connectionState != .connected }) {
            return OnboardingState(step: .verify)
        }
        return OnboardingState(step: .done)
    }

    var prioritizedMenuAlert: MenuAlertState? {
        MenuAlertPolicy.prioritizedAlert(
            isRuntimeAvailable: isCodexRuntimeAvailable,
            runtimeSummary: runtimeProbeSummary,
            lastRefreshError: lastRefreshError,
            accountsNeedingLogin: accountsNeedingLogin
        )
    }

    var preferredMenuAccountCount: Int {
        switch menuDensity {
        case .compact:
            return 5
        case .comfortable:
            return 4
        }
    }

    var limitsCacheTTLMinutes: Int {
        max(1, Int(round(Double(limitsCacheTTLSeconds) / 60.0)))
    }

    var settingsSections: [SettingsSection] {
        [.general, .accounts, .system, .about]
    }

    func menuAccountRows(limit: Int? = nil) -> [AccountRowState] {
        let maxCount = limit ?? preferredMenuAccountCount
        return Array(menuListAccounts.prefix(maxCount)).map { account in
            AccountRowState(account: account, resetDisplayMode: resetDisplayMode)
        }
    }

    func start() {
        guard refreshLoopTask == nil else {
            return
        }

        Task { @MainActor in
            await refreshController.performRefresh(refreshLive: false)
            if shouldPreferLiveRefreshForAutoSwitching {
                await refreshController.performRefresh(refreshLive: true)
            }
        }
        startRefreshLoop()
    }

    func startRefreshLoop() {
        refreshLoopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(limitsCacheTTLSeconds))
                if Task.isCancelled {
                    break
                }
                await refreshController.performRefresh(refreshLive: shouldPreferLiveRefreshForAutoSwitching)
            }
        }
    }

    func refresh() {
        refreshController.triggerRefresh(refreshLive: false)
    }

    func refreshLive() {
        refreshController.triggerRefresh(refreshLive: true)
    }

    func performMenuAlertAction(_ action: MenuAlertState.Action) {
        switch action {
        case .openRuntimeSettings:
            selectSettingsSection(.system)
        case .refreshLive:
            refreshLive()
        case let .relogin(accountName):
            openLoginInTerminal(for: accountName)
        }
    }

    func selectSettingsSection(_ section: SettingsSection) { settingsController.selectSettingsSection(section) }

    func resetOnboardingWizard() {
        selectSettingsAccount(named: nil)
        selectSettingsSection(.general)
    }

    func selectSettingsAccount(named name: String?) { settingsController.selectSettingsAccount(named: name) }

    func setAccountSearchQuery(_ query: String) { settingsController.setAccountSearchQuery(query) }

    func syncSelectedSettingsAccount() { settingsController.syncSelectedSettingsAccount() }

    func setMenuDensity(_ density: MenuDensity) { settingsController.setMenuDensity(density) }

    func setUsageBarStyle(_ style: UsageBarStyle) { settingsController.setUsageBarStyle(style) }

    func setAccountSwitchingStrategy(_ strategy: AccountSwitchingStrategy) { settingsController.setAccountSwitchingStrategy(strategy) }

    func setAutoSwitchNotificationsEnabled(_ isEnabled: Bool) { settingsController.setAutoSwitchNotificationsEnabled(isEnabled) }

    var shouldPreferLiveRefreshForAutoSwitching: Bool {
        accountSwitchingStrategy != .manual
    }

    func setLimitsCacheTTLSeconds(_ seconds: Int) { settingsController.setLimitsCacheTTLSeconds(seconds) }

    func progressValue(for metric: UsageMetric) -> Double {
        guard let usedPercent = metric.usedPercent else {
            return 0
        }
        let usedFraction = min(1, max(0, usedPercent / 100))
        switch usageBarStyle {
        case .depleting:
            return 1 - usedFraction
        case .filling:
            return usedFraction
        }
    }

    func dismissFocusHint() {
        focusedAccountName = nil
    }

    func updateCustomCodexPath(_ value: String) { settingsController.updateCustomCodexPath(value) }

    func clearCustomCodexPath() { settingsController.clearCustomCodexPath() }

    func chooseCustomCodexPath() { settingsController.chooseCustomCodexPath() }

    func switchToAccount(named name: String) { accountManagement.switchToAccount(named: name) }

    func startNewAccountLogin() { accountManagement.startNewAccountLogin() }

    func renameAccount(from oldName: String, to rawNewName: String) { accountManagement.renameAccount(from: oldName, to: rawNewName) }

    func removeAccount(named name: String, deleteData: Bool) { accountManagement.removeAccount(named: name, deleteData: deleteData) }

    func importCurrentAuth(into name: String) { accountManagement.importCurrentAuth(into: name) }

    func checkLoginStatus(for name: String) { accountManagement.checkLoginStatus(for: name) }

    func startLoginFlow(accountName: String, createIfNeeded: Bool) { accountActions.startLoginFlow(accountName: accountName, createIfNeeded: createIfNeeded) }

    func openLoginInTerminal(for name: String) { accountManagement.openLoginInTerminal(for: name) }

    func clearAccountActionFeedback() { accountManagement.clearAccountActionFeedback() }

    func runSwitchAction(
        named name: String,
        operation: @escaping () async throws -> Void
    ) {
        guard switchingAccountName == nil else {
            return
        }

        Task {
            switchingAccountName = name
            defer { switchingAccountName = nil }

            do {
                try await operation()
            } catch {
                lastRefreshError = error.localizedDescription
                cliResolutionHint = accountService.resolutionHint
            }
        }
    }

    func clearFocusedAccountIfMissing() {
        if let focusedAccountName,
           !accounts.contains(where: { $0.name == focusedAccountName })
        {
            self.focusedAccountName = nil
        }
    }

    // MARK: - Account List Mutation Helpers

    /// Sorts accounts with current first, then by name.
    private func sortedCurrentFirst(_ accounts: [AccountUsage]) -> [AccountUsage] {
        accounts.sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent {
                return lhs.isCurrent
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Creates a copy of an AccountUsage with specified field overrides.
    private func copyAccount(
        _ account: AccountUsage,
        name: String? = nil,
        isCurrent: Bool? = nil,
        hasAuth: Bool? = nil,
        lastUsedAt: String? = nil,
        lastLoginStatus: String? = nil,
        defaultWorkspaceEmail: String? = nil,
        usage: UsageSummary? = nil,
        source: String? = nil,
        usageError: String? = nil
    ) -> AccountUsage {
        AccountUsage(
            name: name ?? account.name,
            isCurrent: isCurrent ?? account.isCurrent,
            hasAuth: hasAuth ?? account.hasAuth,
            lastUsedAt: lastUsedAt ?? account.lastUsedAt,
            lastLoginStatus: lastLoginStatus ?? account.lastLoginStatus,
            defaultWorkspaceEmail: defaultWorkspaceEmail ?? account.defaultWorkspaceEmail,
            usage: usage ?? account.usage,
            source: source ?? account.source,
            usageError: usageError ?? account.usageError
        )
    }

    /// Updates the accounts array and applies current-first sorting.
    private func updateAccounts(_ newAccounts: [AccountUsage]) {
        accounts = sortedCurrentFirst(newAccounts)
    }

    /// Applies local state change when the current account is switched.
    func applyCurrentAccountLocally(named name: String) {
        updateAccounts(accounts.map { copyAccount($0, isCurrent: $0.name == name) })
    }

    /// Renames an account locally and updates focused/selected references.
    func renameAccountLocally(from oldName: String, to newName: String) {
        updateAccounts(accounts.map { account in
            copyAccount(account, name: account.name == oldName ? newName : account.name)
        })

        if focusedAccountName == oldName {
            focusedAccountName = newName
        }
    }

    /// Removes an account locally and optionally updates the current account marker.
    func removeAccountLocally(named name: String, currentAccountName: String?) {
        updateAccounts(
            accounts
                .filter { $0.name != name }
                .map { account in
                    copyAccount(
                        account,
                        isCurrent: currentAccountName.map { account.name == $0 } ?? account.isCurrent
                    )
                }
        )

        clearFocusedAccountIfMissing()
        syncSelectedSettingsAccount()
    }

    /// Upserts an authenticated account locally, preserving existing data where not overridden.
    func upsertAuthenticatedAccountLocally(
        named name: String,
        currentAccountName: String? = nil,
        lastLoginStatus: String? = nil
    ) {
        let nowISO = CodexAccountService.nowFormatter.string(from: Date())
        var didUpdateExisting = false

        let updated = accounts.map { account in
            guard account.name == name else {
                return copyAccount(
                    account,
                    isCurrent: currentAccountName.map { account.name == $0 } ?? account.isCurrent
                )
            }

            didUpdateExisting = true
            return copyAccount(
                account,
                isCurrent: currentAccountName.map { name == $0 } ?? account.isCurrent,
                hasAuth: true,
                lastUsedAt: nowISO,
                lastLoginStatus: lastLoginStatus ?? account.lastLoginStatus
            )
        }

        if didUpdateExisting {
            updateAccounts(updated)
        } else {
            let newAccount = AccountUsage(
                name: name,
                isCurrent: currentAccountName == name,
                hasAuth: true,
                lastUsedAt: nowISO,
                lastLoginStatus: lastLoginStatus,
                defaultWorkspaceEmail: nil,
                usage: UsageFormatter.usageSummary(from: nil),
                source: "-",
                usageError: nil
            )
            updateAccounts(updated + [newAccount])
        }

        syncSelectedSettingsAccount()
    }

    func sendTestAutoSwitchNotification() { accountManagement.sendTestAutoSwitchNotification() }

    func setResetDisplayMode(_ mode: ResetDisplayMode) { settingsController.setResetDisplayMode(mode) }

    func openMulticodexConfigDirectory() { accountManagement.openMulticodexConfigDirectory() }


}
