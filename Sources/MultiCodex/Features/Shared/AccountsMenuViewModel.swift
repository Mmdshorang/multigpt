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
    @Published var sequentialLoginState: SequentialLoginState?
    @Published var customCodexPath: String
    @Published var resetDisplayMode: ResetDisplayMode
    @Published var selectedSettingsSection: SettingsSection
    @Published var selectedSettingsAccountName: String?
    @Published var accountSearchQuery: String
    @Published var menuDensity: MenuDensity
    @Published var usageBarStyle: UsageBarStyle
    @Published var accountSortCriterion: AccountSortCriterion
    @Published var accountSortWindow: AccountSortWindow
    @Published var accountSortDirection: SortDirection
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
    var sequentialLoginTask: Task<Void, Never>?
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
        accountSortCriterion = preferences.accountSortCriterion
        accountSortWindow = preferences.accountSortWindow
        accountSortDirection = preferences.accountSortDirection
        accountSwitchingStrategy = preferences.accountSwitchingStrategy
        autoSwitchNotificationsEnabled = preferences.autoSwitchNotificationsEnabled
        let persistedTTL = preferences.limitsCacheTTLSeconds
        limitsCacheTTLSeconds = CodexAccountService.normalizedLimitsCacheTTLSeconds(
            persistedTTL > 0 ? persistedTTL : CodexAccountService.defaultLimitsCacheTTLSeconds
        )
        self.accountService.customCodexPath = customCodexPath.isEmpty ? nil : customCodexPath
        self.accountService.limitsCacheTTLSeconds = limitsCacheTTLSeconds
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
        sequentialLoginTask?.cancel()
        refreshLoopTask?.cancel()
    }

    var currentAccount: AccountUsage? {
        accounts.first(where: { $0.isCurrent })
    }

    var menuBarTitle: String {
        guard let current = currentAccount else {
            return accounts.isEmpty ? "mcx" : "mcx ?"
        }

        if let percent = compactPercentText(for: current.usage) {
            return "mcx \(percent)"
        }

        return "mcx \(current.name)"
    }

    var menuBarSymbol: String {
        if lastRefreshError != nil {
            return "exclamationmark.triangle.fill"
        }

        let constrainedUsedPercent = currentAccount.flatMap { compactUsedPercent(for: $0.usage) }
        switch UsageLevel.from(usedPercent: constrainedUsedPercent) {
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
        let sortedForSettings = accounts.sorted { lhs, rhs in
            compareAccounts(lhs, rhs)
        }
        let query = accountSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return sortedForSettings
        }

        return sortedForSettings.filter { account in
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

    func setAccountSortCriterion(_ criterion: AccountSortCriterion) {
        guard criterion != accountSortCriterion else {
            return
        }
        accountSortCriterion = criterion
        preferences.accountSortCriterion = criterion
        resortAccounts()
    }

    func setAccountSortWindow(_ window: AccountSortWindow) {
        guard window != accountSortWindow else {
            return
        }
        accountSortWindow = window
        preferences.accountSortWindow = window
        resortAccounts()
    }

    func setAccountSortDirection(_ direction: SortDirection) {
        guard direction != accountSortDirection else {
            return
        }
        accountSortDirection = direction
        preferences.accountSortDirection = direction
        resortAccounts()
    }

    func setAccountSwitchingStrategy(_ strategy: AccountSwitchingStrategy) { settingsController.setAccountSwitchingStrategy(strategy) }

    func setAutoSwitchNotificationsEnabled(_ isEnabled: Bool) { settingsController.setAutoSwitchNotificationsEnabled(isEnabled) }

    var shouldPreferLiveRefreshForAutoSwitching: Bool {
        accountSwitchingStrategy != .manual
    }

    func setLimitsCacheTTLSeconds(_ seconds: Int) { settingsController.setLimitsCacheTTLSeconds(seconds) }

    func progressValue(for metric: UsageMetric) -> Double {
        progressValue(fromUsedFraction: usedFraction(for: metric))
    }

    func displayPercentText(for metric: UsageMetric) -> String {
        guard let usedPercent = metric.usedPercent else {
            return "-"
        }
        let value: Double
        switch usageBarStyle {
        case .depleting:
            value = 100 - usedPercent
        case .filling:
            value = usedPercent
        }
        return Self.formatPercent(value)
    }

    func compactProgressValue(for usage: UsageSummary) -> Double {
        guard let usedPercent = compactUsedPercent(for: usage) else {
            return 0
        }
        return progressValue(fromUsedFraction: min(1, max(0, usedPercent / 100)))
    }

    func compactUsedPercent(for usage: UsageSummary) -> Double? {
        constrainedMetric(in: usage)?.usedPercent
    }

    func compactPercentText(for usage: UsageSummary) -> String? {
        guard let constrainedMetric = constrainedMetric(in: usage) else {
            return nil
        }
        return displayPercentText(for: constrainedMetric)
    }

    private func usedFraction(for metric: UsageMetric) -> Double {
        guard let usedPercent = metric.usedPercent else {
            return 0
        }
        return min(1, max(0, usedPercent / 100))
    }

    private func progressValue(fromUsedFraction usedFraction: Double) -> Double {
        switch usageBarStyle {
        case .depleting:
            return 1 - usedFraction
        case .filling:
            return usedFraction
        }
    }

    private func constrainedMetric(in usage: UsageSummary) -> UsageMetric? {
        let fiveHourUsed = usage.fiveHour.usedPercent
        let weeklyUsed = usage.weekly.usedPercent
        switch (fiveHourUsed, weeklyUsed) {
        case let (fiveHour?, weekly?):
            return fiveHour >= weekly ? usage.fiveHour : usage.weekly
        case (_?, nil):
            return usage.fiveHour
        case (nil, _?):
            return usage.weekly
        case (nil, nil):
            return nil
        }
    }

    private static func formatPercent(_ value: Double) -> String {
        let clampedValue = min(100, max(0, value))
        let rounded = (clampedValue * 10.0).rounded() / 10.0
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f%%", rounded)
        }
        return String(format: "%.1f%%", rounded)
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

    func prepareSequentialNewAccountLogin(count: Int) {
        accountManagement.prepareSequentialNewAccountLogin(count: count)
    }

    func startSequentialNewAccountLogin() {
        accountManagement.startSequentialNewAccountLogin()
    }

    func cancelSequentialNewAccountLogin() {
        accountManagement.cancelSequentialNewAccountLogin()
    }

    func retryFailedSequentialNewAccountLogin() {
        accountManagement.retryFailedSequentialNewAccountLogin()
    }

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

    var accountSortMenuLabel: String {
        switch accountSortCriterion {
        case .name:
            return accountSortDirection == .ascending ? "Name A→Z" : "Name Z→A"
        case .used, .remaining:
            return "\(accountSortCriterion.title) (\(accountSortWindow.title.lowercased())) \(accountSortDirection.arrowSymbol)"
        }
    }

    // MARK: - Account List Mutation Helpers

    /// Sorts accounts with the current account pinned first, then by the active sort policy.
    private func sortedAccounts(_ accounts: [AccountUsage]) -> [AccountUsage] {
        let currentAccounts = accounts.filter(\.isCurrent)
        let otherAccounts = accounts.filter { !$0.isCurrent }
        let sortedOthers = otherAccounts.sorted { lhs, rhs in
            compareAccounts(lhs, rhs)
        }
        return currentAccounts + sortedOthers
    }

    private func compareAccounts(_ lhs: AccountUsage, _ rhs: AccountUsage) -> Bool {
        switch accountSortCriterion {
        case .name:
            return compareNames(lhs.name, rhs.name, direction: accountSortDirection)
        case .used, .remaining:
            let lhsValue = sortValue(for: lhs)
            let rhsValue = sortValue(for: rhs)

            switch (lhsValue, rhsValue) {
            case let (lhsValue?, rhsValue?):
                if lhsValue != rhsValue {
                    return accountSortDirection == .ascending ? lhsValue < rhsValue : lhsValue > rhsValue
                }
                return compareNames(lhs.name, rhs.name, direction: .ascending)
            case (nil, nil):
                return compareNames(lhs.name, rhs.name, direction: .ascending)
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }
    }

    private func compareNames(_ lhs: String, _ rhs: String, direction: SortDirection) -> Bool {
        let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
        if comparison == .orderedSame {
            return lhs < rhs
        }

        switch direction {
        case .ascending:
            return comparison == .orderedAscending
        case .descending:
            return comparison == .orderedDescending
        }
    }

    private func sortValue(for account: AccountUsage) -> Double? {
        switch accountSortCriterion {
        case .name:
            return nil
        case .used:
            switch accountSortWindow {
            case .fiveHour:
                return account.usage.fiveHour.usedPercent
            case .weekly:
                return account.usage.weekly.usedPercent
            }
        case .remaining:
            switch accountSortWindow {
            case .fiveHour:
                guard let usedPercent = account.usage.fiveHour.usedPercent else {
                    return nil
                }
                return 100 - usedPercent
            case .weekly:
                guard let usedPercent = account.usage.weekly.usedPercent else {
                    return nil
                }
                return 100 - usedPercent
            }
        }
    }

    private func resortAccounts() {
        accounts = sortedAccounts(accounts)
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

    /// Updates the accounts array and applies the active shared sort policy.
    func updateAccounts(_ newAccounts: [AccountUsage]) {
        accounts = sortedAccounts(newAccounts)
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
