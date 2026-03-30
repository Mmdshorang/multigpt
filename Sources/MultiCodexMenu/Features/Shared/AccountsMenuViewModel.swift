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
    @Published var isUsingTemporaryAuthSandbox = false
    @Published var temporaryAuthSandboxHome: String?
    @Published var customCodexPath: String
    @Published var resetDisplayMode: ResetDisplayMode
    @Published var selectedSettingsSection: SettingsSection
    @Published var selectedSettingsAccountName: String?
    @Published var accountSearchQuery: String
    @Published var hasCompletedOnboarding: Bool
    @Published var isAdvancedSettingsVisible: Bool
    @Published var menuDensity: MenuDensity
    @Published var usageBarStyle: UsageBarStyle
    @Published var accountSwitchingStrategy: AccountSwitchingStrategy
    @Published var autoSwitchNotificationsEnabled: Bool
    @Published var limitsCacheTTLSeconds: Int
    @Published var pendingAccountRemovalRequest: PendingAccountRemovalRequest?

    let accountService: any CodexAccountServicing
    let fileManager: FileManager
    private let autoSwitchNotifierFactory: () -> any AutoSwitchNotificationSending
    var preferences: AppPreferencesStore

    var refreshLoopTask: Task<Void, Never>?
    var didBecomeActiveObserver: NSObjectProtocol?
    var pendingInteractiveLoginSession: PendingInteractiveLoginSession?
    var feedbackAutoClearTask: Task<Void, Never>?
    lazy var autoSwitchNotifier: any AutoSwitchNotificationSending = autoSwitchNotifierFactory()

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
        hasCompletedOnboarding = preferences.hasCompletedOnboarding
        isAdvancedSettingsVisible = preferences.isAdvancedSettingsVisible
        menuDensity = preferences.menuDensity
        usageBarStyle = preferences.usageBarStyle
        accountSwitchingStrategy = preferences.accountSwitchingStrategy
        autoSwitchNotificationsEnabled = preferences.autoSwitchNotificationsEnabled
        let persistedTTL = preferences.limitsCacheTTLSeconds
        limitsCacheTTLSeconds = CodexAccountService.normalizedLimitsCacheTTLSeconds(
            persistedTTL > 0 ? persistedTTL : CodexAccountService.defaultLimitsCacheTTLSeconds
        )
        pendingAccountRemovalRequest = nil
        if !isAdvancedSettingsVisible, selectedSettingsSection == .advanced {
            selectedSettingsSection = .dashboard
        }
#if DEBUG
        isUsingTemporaryAuthSandbox = preferences.temporaryAuthSandboxEnabled
        temporaryAuthSandboxHome = preferences.temporaryAuthSandboxHome
#else
        isUsingTemporaryAuthSandbox = false
        temporaryAuthSandboxHome = nil
#endif
        self.accountService.customCodexPath = customCodexPath.isEmpty ? nil : customCodexPath
        self.accountService.limitsCacheTTLSeconds = limitsCacheTTLSeconds
        if autoSwitchNotificationsEnabled {
            self.autoSwitchNotifier.requestAuthorizationIfNeeded()
        }
        configureSandboxEnvironment()
        refreshRuntimeProbe()
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDidBecomeActive()
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
        if hasCompletedOnboarding {
            return OnboardingState(step: .done)
        }
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

        triggerRefresh(refreshLive: false)
        startRefreshLoop()
    }

    func startRefreshLoop() {
        refreshLoopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(limitsCacheTTLSeconds))
                if Task.isCancelled {
                    break
                }
                await performRefresh(refreshLive: false)
            }
        }
    }

    func refresh() {
        triggerRefresh(refreshLive: false)
    }

    func refreshLive() {
        triggerRefresh(refreshLive: true)
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

    func selectSettingsSection(_ section: SettingsSection) {
        if section == .advanced, !isAdvancedSettingsVisible {
            setAdvancedSettingsVisible(true)
        }
        selectedSettingsSection = section
        preferences.selectedSettingsSection = section
    }

    func selectSettingsAccount(named name: String?) {
        selectedSettingsAccountName = name
        preferences.selectedSettingsAccountName = name
    }

    func setAccountSearchQuery(_ query: String) {
        accountSearchQuery = query
        syncSelectedSettingsAccount()
    }

    func setAdvancedSettingsVisible(_ isVisible: Bool) {
        isAdvancedSettingsVisible = isVisible
        preferences.isAdvancedSettingsVisible = isVisible
        if !isVisible, selectedSettingsSection == .advanced {
            selectSettingsSection(.dashboard)
        }
    }

    func setMenuDensity(_ density: MenuDensity) {
        guard density != menuDensity else {
            return
        }
        menuDensity = density
        preferences.menuDensity = density
    }

    func setUsageBarStyle(_ style: UsageBarStyle) {
        guard style != usageBarStyle else {
            return
        }
        usageBarStyle = style
        preferences.usageBarStyle = style
    }

    func setAccountSwitchingStrategy(_ strategy: AccountSwitchingStrategy) {
        guard strategy != accountSwitchingStrategy else {
            return
        }
        accountSwitchingStrategy = strategy
        preferences.accountSwitchingStrategy = strategy
    }

    func setAutoSwitchNotificationsEnabled(_ isEnabled: Bool) {
        guard isEnabled != autoSwitchNotificationsEnabled else {
            return
        }
        autoSwitchNotificationsEnabled = isEnabled
        preferences.autoSwitchNotificationsEnabled = isEnabled
        if isEnabled {
            autoSwitchNotifier.requestAuthorizationIfNeeded()
        }
    }

    func setLimitsCacheTTLSeconds(_ seconds: Int) {
        let normalized = CodexAccountService.normalizedLimitsCacheTTLSeconds(seconds)
        guard normalized != limitsCacheTTLSeconds else {
            return
        }
        limitsCacheTTLSeconds = normalized
        preferences.limitsCacheTTLSeconds = normalized
        accountService.limitsCacheTTLSeconds = normalized

        // Refresh cadence is tied to TTL, so restart the loop when this changes.
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        startRefreshLoop()
    }

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

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
        preferences.hasCompletedOnboarding = true
    }

    func resetOnboardingProgress() {
        hasCompletedOnboarding = false
        preferences.hasCompletedOnboarding = false
    }

    func beginAccountRemoval(named name: String, deleteData: Bool) {
        pendingAccountRemovalRequest = PendingAccountRemovalRequest(accountName: name, deleteData: deleteData)
    }

    func cancelPendingAccountRemoval() {
        pendingAccountRemovalRequest = nil
    }

    func executePendingAccountRemoval(confirming typedName: String?) {
        guard let request = pendingAccountRemovalRequest else {
            return
        }

        if request.deleteData {
            let normalizedTyped = (typedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedTyped != request.accountName {
                setAccountFeedback(message: nil, error: "Type the account name to confirm delete-data removal.")
                return
            }
        }

        pendingAccountRemovalRequest = nil
        removeAccount(named: request.accountName, deleteData: request.deleteData)
    }

    func switchToAccount(named name: String) {
        runSwitchAction(named: name) {
            try await self.accountService.switchAccount(name: name)
            self.lastRefreshError = nil
            self.accounts = self.accounts.map { account in
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
            self.focusedAccountName = name
            self.syncSelectedSettingsAccount()
            self.setAccountFeedback(message: "Now using \(name).", error: nil)
            Task { @MainActor in
                await self.performRefresh(refreshLive: false, allowAutoSwitch: false)
            }
        }
    }

    func startNewAccountLogin() {
        let generatedName = generateRandomAccountName()
        startLoginFlow(accountName: generatedName, createIfNeeded: true)
    }

    func renameAccount(from oldName: String, to rawNewName: String) {
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            accountActionError = "New account name cannot be empty."
            accountActionMessage = nil
            return
        }

        guard oldName != newName else {
            accountActionError = nil
            accountActionMessage = "Account name is unchanged."
            return
        }

        runAccountAction(for: oldName) {
            _ = try await self.accountService.renameAccount(from: oldName, to: newName)
            if self.selectedSettingsAccountName == oldName {
                self.selectSettingsAccount(named: newName)
            }
            return .success("Renamed \(oldName) to \(newName).")
        }
    }

    func removeAccount(named name: String, deleteData: Bool) {
        if pendingAccountRemovalRequest?.accountName == name {
            pendingAccountRemovalRequest = nil
        }
        runAccountAction(for: name) {
            _ = try await self.accountService.removeAccount(name: name, deleteData: deleteData)
            if self.selectedSettingsAccountName == name {
                self.selectSettingsAccount(named: nil)
            }
            return .success(deleteData ? "Removed \(name) and deleted stored data." : "Removed \(name).")
        }
    }

    func importCurrentAuth(into name: String) {
        runAccountAction(for: name) {
            _ = try await self.accountService.importDefaultAuth(into: name)
            return .success("Imported current ~/.codex/auth.json into \(name).")
        }
    }

    func checkLoginStatus(for name: String) {
        runAccountAction(for: name) {
            let status = try await self.accountService.fetchStatus(name: name)
            return self.statusOutcome(for: name, status: status, successFallback: "\(name): login status is OK.")
        }
    }

    func openLoginInTerminal(for name: String) {
        startLoginFlow(accountName: name, createIfNeeded: false)
    }

    func clearAccountActionFeedback() {
        feedbackAutoClearTask?.cancel()
        feedbackAutoClearTask = nil
        setAccountFeedback(message: nil, error: nil)
    }

    func sendTestAutoSwitchNotification() {
        guard autoSwitchNotificationsEnabled else {
            setAccountFeedback(message: nil, error: "Enable auto-switch notifications to send a test.")
            return
        }

        let previousAccountName = currentAccount?.name ?? accounts.first?.name ?? "alpha"
        let newAccountName = accounts.first(where: { $0.name != previousAccountName })?.name ?? "beta"
        let payload = AutoSwitchNotificationPayload(
            previousAccountName: previousAccountName,
            newAccountName: newAccountName,
            reason: "5h window expiring"
        )

        autoSwitchNotifier.send(payload)
        setAccountFeedback(
            message: "Sent test notification \(previousAccountName) -> \(newAccountName).",
            error: nil
        )
    }

    func setResetDisplayMode(_ mode: ResetDisplayMode) {
        guard mode != resetDisplayMode else {
            return
        }
        resetDisplayMode = mode
        preferences.resetDisplayMode = mode
    }

    func openMulticodexConfigDirectory() {
        let url = URL(fileURLWithPath: accountService.effectiveMulticodexHomePath(), isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    func enableTemporaryAuthSandbox() {
        do {
            let sandboxHome = try prepareFreshTemporaryAuthSandbox()
            temporaryAuthSandboxHome = sandboxHome
            isUsingTemporaryAuthSandbox = true
            preferences.temporaryAuthSandboxEnabled = true
            preferences.temporaryAuthSandboxHome = sandboxHome
            configureSandboxEnvironment()
            setAccountFeedback(
                message: "Temporary auth sandbox enabled at \(sandboxHome).",
                error: nil
            )
            refreshLive()
        } catch {
            setAccountFeedback(message: nil, error: "Could not enable temporary auth sandbox: \(error.localizedDescription)")
        }
    }

    func resetTemporaryAuthSandbox() {
        enableTemporaryAuthSandbox()
    }

    func disableTemporaryAuthSandbox() {
        isUsingTemporaryAuthSandbox = false
        preferences.temporaryAuthSandboxEnabled = false
        configureSandboxEnvironment()
        setAccountFeedback(message: "Temporary auth sandbox disabled. Using your regular setup.", error: nil)
        refreshLive()
    }

    func setTemporaryAuthSandboxEnabled(_ enabled: Bool) {
        guard enabled != isUsingTemporaryAuthSandbox else {
            return
        }
        if enabled {
            enableTemporaryAuthSandbox()
        } else {
            disableTemporaryAuthSandbox()
        }
    }

}
