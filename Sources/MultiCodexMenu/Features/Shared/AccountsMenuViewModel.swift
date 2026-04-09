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
    @Published var isAdvancedSettingsVisible: Bool
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
        isAdvancedSettingsVisible = false
        menuDensity = preferences.menuDensity
        usageBarStyle = preferences.usageBarStyle
        accountSwitchingStrategy = preferences.accountSwitchingStrategy
        autoSwitchNotificationsEnabled = preferences.autoSwitchNotificationsEnabled
        let persistedTTL = preferences.limitsCacheTTLSeconds
        limitsCacheTTLSeconds = CodexAccountService.normalizedLimitsCacheTTLSeconds(
            persistedTTL > 0 ? persistedTTL : CodexAccountService.defaultLimitsCacheTTLSeconds
        )
        if !isAdvancedSettingsVisible, selectedSettingsSection == .advanced {
            selectedSettingsSection = .dashboard
        }
        self.accountService.customCodexPath = customCodexPath.isEmpty ? nil : customCodexPath
        self.accountService.limitsCacheTTLSeconds = limitsCacheTTLSeconds
        if autoSwitchNotificationsEnabled {
            self.autoSwitchNotifier.requestAuthorizationIfNeeded()
        }
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
        var sections: [SettingsSection] = [
            .dashboard,
            .accounts,
            .runtime,
            .display,
            .troubleshooting,
        ]
        if isAdvancedSettingsVisible {
            sections.append(.advanced)
        }
        return sections
    }

    func menuAccountRows(limit: Int? = nil) -> [AccountRowState] {
        let maxCount = limit ?? preferredMenuAccountCount
        return Array(accounts.prefix(maxCount)).map { account in
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
            selectSettingsSection(.runtime)
        case .refreshLive:
            refreshLive()
        case let .relogin(accountName):
            openLoginInTerminal(for: accountName)
        }
    }

    func selectSettingsSection(_ section: SettingsSection) { settingsController.selectSettingsSection(section) }

    func resetOnboardingWizard() {
        selectSettingsAccount(named: nil)
        selectSettingsSection(.runtime)
    }

    func selectSettingsAccount(named name: String?) { settingsController.selectSettingsAccount(named: name) }

    func setAccountSearchQuery(_ query: String) { settingsController.setAccountSearchQuery(query) }

    func syncSelectedSettingsAccount() { settingsController.syncSelectedSettingsAccount() }

    func setAdvancedSettingsVisible(_ isVisible: Bool) { settingsController.setAdvancedSettingsVisible(isVisible) }

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

    func applyCurrentAccountLocally(named name: String) {
        accounts = accounts.map { account in
            AccountUsage(
                name: account.name,
                isCurrent: account.name == name,
                hasAuth: account.hasAuth,
                lastUsedAt: account.lastUsedAt,
                lastLoginStatus: account.lastLoginStatus,
                usage: account.usage,
                source: account.source,
                usageError: account.usageError
            )
        }
    }

    func clearFocusedAccountIfMissing() {
        if let focusedAccountName,
           !accounts.contains(where: { $0.name == focusedAccountName })
        {
            self.focusedAccountName = nil
        }
    }

    func sendTestAutoSwitchNotification() { accountManagement.sendTestAutoSwitchNotification() }

    func setResetDisplayMode(_ mode: ResetDisplayMode) { settingsController.setResetDisplayMode(mode) }

    func openMulticodexConfigDirectory() { accountManagement.openMulticodexConfigDirectory() }


}
