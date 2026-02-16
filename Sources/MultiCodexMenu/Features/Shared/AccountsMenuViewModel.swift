import AppKit
import Foundation

@MainActor
final class AccountsMenuViewModel: ObservableObject {
    @Published private(set) var accounts: [AccountUsage] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshError: String?
    @Published private(set) var refreshWarningMessage: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var switchingAccountName: String?
    @Published private(set) var cliResolutionHint: String?
    @Published private(set) var accountActionInFlightName: String?
    @Published private(set) var accountActionMessage: String?
    @Published private(set) var accountActionError: String?
    @Published private(set) var runtimeProbeSummary: String?
    @Published private(set) var isCodexRuntimeAvailable = false
    @Published private(set) var focusedAccountName: String?
    @Published private(set) var isUsingTemporaryAuthSandbox = false
    @Published private(set) var temporaryAuthSandboxHome: String?
    @Published var customCodexPath: String
    @Published var resetDisplayMode: ResetDisplayMode
    @Published private(set) var selectedSettingsSection: SettingsSection
    @Published private(set) var selectedSettingsAccountName: String?
    @Published private(set) var accountSearchQuery: String
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var isAdvancedSettingsVisible: Bool
    @Published private(set) var menuDensity: MenuDensity
    @Published private(set) var usageBarStyle: UsageBarStyle
    @Published private(set) var limitsCacheTTLSeconds: Int
    @Published private(set) var pendingAccountRemovalRequest: PendingAccountRemovalRequest?

    private let accountService: any CodexAccountServicing
    private let fileManager: FileManager
    private var preferences: AppPreferencesStore

    private var refreshLoopTask: Task<Void, Never>?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var pendingInteractiveLoginAccount: String?
    private var feedbackAutoClearTask: Task<Void, Never>?

    init(
        accountService: any CodexAccountServicing = CodexAccountService(),
        fileManager: FileManager = .default,
        preferences: AppPreferencesStore = AppPreferencesStore(),
        startImmediately: Bool = true
    ) {
        self.accountService = accountService
        self.fileManager = fileManager
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

    private func startRefreshLoop() {
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
            self.setAccountFeedback(message: "Now using \(name).", error: nil)
            await self.performRefresh(refreshLive: true)
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

    func toggleResetDisplayMode() {
        let nextMode = resetDisplayMode.next
        resetDisplayMode = nextMode
        preferences.resetDisplayMode = nextMode
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

    func openTemporaryAuthSandboxDirectory() {
        guard let sandbox = temporaryAuthSandboxHome, !sandbox.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: sandbox, isDirectory: true))
    }

    func updateCustomCodexPath(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        customCodexPath = trimmed
        preferences.customCodexPath = trimmed
        accountService.customCodexPath = trimmed.isEmpty ? nil : trimmed
        refreshRuntimeProbe()
        refresh()
    }

    func clearCustomCodexPath() {
        updateCustomCodexPath("")
    }

    func dismissFocusHint() {
        focusedAccountName = nil
    }

    func chooseCustomCodexPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Use"
        panel.message = "Choose the codex executable"

        if panel.runModal() == .OK, let path = panel.url?.path {
            updateCustomCodexPath(path)
        }
    }

    private func performRefresh(refreshLive: Bool) async {
        if pendingInteractiveLoginAccount != nil {
            return
        }

        if isRefreshing {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let previousAccounts = accounts

        do {
            let fetchedAccounts = try await accountService.fetchAccounts()
            let limits = try await accountService.fetchLimits(refreshLive: refreshLive)

            accounts = AccountUsageMergeService.mergeAccounts(
                accounts: fetchedAccounts,
                limits: limits,
                previousAccounts: previousAccounts
            )
            if let focused = focusedAccountName, !accounts.contains(where: { $0.name == focused }) {
                focusedAccountName = nil
            }
            syncSelectedSettingsAccount()
            if !hasCompletedOnboarding && onboardingState.step == .done {
                markOnboardingCompleted()
            }
            lastUpdatedAt = Date()
            cliResolutionHint = accountService.resolutionHint

            if limits.errors.isEmpty {
                lastRefreshError = nil
                refreshWarningMessage = nil
            } else {
                let count = limits.errors.count
                let suffix = count == 1 ? "account" : "accounts"
                lastRefreshError = nil
                refreshWarningMessage = "Showing latest data. Could not refresh \(count) \(suffix)."
            }
        } catch {
            cliResolutionHint = accountService.resolutionHint
            if previousAccounts.isEmpty {
                lastRefreshError = error.localizedDescription
                refreshWarningMessage = nil
            } else {
                lastRefreshError = nil
                refreshWarningMessage = "Refresh failed. Showing latest data."
            }
        }
    }

    private enum AccountActionOutcome {
        case success(String)
        case failure(String)
    }

    private func setAccountFeedback(message: String?, error: String?) {
        accountActionMessage = message
        accountActionError = error
        feedbackAutoClearTask?.cancel()
        feedbackAutoClearTask = nil
        guard message != nil else {
            return
        }
        feedbackAutoClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled {
                return
            }
            accountActionMessage = nil
        }
    }

    private func triggerRefresh(refreshLive: Bool) {
        Task {
            await performRefresh(refreshLive: refreshLive)
        }
    }

    private func startLoginFlow(accountName: String, createIfNeeded: Bool) {
        guard accountActionInFlightName == nil, pendingInteractiveLoginAccount == nil else {
            return
        }

        Task {
            accountActionInFlightName = accountName
            focusedAccountName = accountName
            feedbackAutoClearTask?.cancel()
            feedbackAutoClearTask = nil
            accountActionMessage = "Opening browser login for \(accountName)..."
            accountActionError = nil

            defer {
                accountActionInFlightName = nil
            }

            do {
                _ = try await accountService.loginInApp(account: accountName, createIfNeeded: createIfNeeded)
                _ = try await accountService.importDefaultAuth(into: accountName)
                let status = try await accountService.fetchStatus(name: accountName)

                switch statusOutcome(
                    for: accountName,
                    status: status,
                    successFallback: "Login synced to \(accountName)."
                ) {
                case let .success(message):
                    setAccountFeedback(message: message, error: nil)
                case let .failure(message):
                    setAccountFeedback(message: nil, error: message)
                }

                await performRefresh(refreshLive: true)
            } catch {
                if shouldFallbackToTerminal(error) {
                    launchTerminalLoginFallback(accountName: accountName, createIfNeeded: createIfNeeded, rootError: error)
                } else {
                    setAccountFeedback(message: nil, error: error.localizedDescription)
                }
            }
        }
    }

    private func shouldFallbackToTerminal(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("tty")
            || text.contains("not interactive")
            || text.contains("stdin")
            || text.contains("standard input")
    }

    private func launchTerminalLoginFallback(accountName: String, createIfNeeded: Bool, rootError: Error) {
        do {
            if createIfNeeded {
                try accountService.openNewAccountLoginInTerminal(newAccountName: accountName)
            } else {
                try accountService.openLoginInTerminal(account: accountName)
            }
            pendingInteractiveLoginAccount = accountName
            setAccountFeedback(
                message: "Using Terminal fallback for \(accountName). Complete login and return to MultiCodex.",
                error: nil
            )
        } catch {
            setAccountFeedback(
                message: nil,
                error: "\(rootError.localizedDescription) (Fallback failed: \(error.localizedDescription))"
            )
        }
    }

    private func statusOutcome(
        for accountName: String,
        status: AccountStatusPayload,
        successFallback: String
    ) -> AccountActionOutcome {
        let summary = status.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if status.exitCode == 0 {
            return .success(summary.isEmpty ? successFallback : "\(accountName): \(summary)")
        }
        return .failure(summary.isEmpty ? "\(accountName): login check failed." : "\(accountName): \(summary)")
    }

    private func runAccountAction(
        for accountName: String,
        operation: @escaping () async throws -> AccountActionOutcome
    ) {
        guard accountActionInFlightName == nil else {
            return
        }

        Task {
            accountActionInFlightName = accountName
            defer { accountActionInFlightName = nil }

            do {
                switch try await operation() {
                case let .success(message):
                    setAccountFeedback(message: message, error: nil)
                case let .failure(message):
                    setAccountFeedback(message: nil, error: message)
                }
                await performRefresh(refreshLive: false)
            } catch {
                setAccountFeedback(message: nil, error: error.localizedDescription)
            }
        }
    }

    private func runSwitchAction(
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

    private func handleDidBecomeActive() {
        guard let pendingAccount = pendingInteractiveLoginAccount else {
            refreshLive()
            return
        }

        pendingInteractiveLoginAccount = nil
        focusedAccountName = pendingAccount
        runAccountAction(for: pendingAccount) {
            _ = try await self.accountService.importDefaultAuth(into: pendingAccount)
            let status = try await self.accountService.fetchStatus(name: pendingAccount)
            return self.statusOutcome(
                for: pendingAccount,
                status: status,
                successFallback: "Login synced to \(pendingAccount). You can rename it anytime."
            )
        }
    }

    private func refreshRuntimeProbe() {
        let probe = accountService.probeRuntime()
        isCodexRuntimeAvailable = probe.isAvailable
        runtimeProbeSummary = probe.summary
    }

    private func configureSandboxEnvironment() {
        guard isUsingTemporaryAuthSandbox else {
            accountService.sandboxHomeDirectory = nil
            accountService.sandboxMulticodexHomeDirectory = nil
            return
        }

        if let sandboxHome = temporaryAuthSandboxHome?.trimmingCharacters(in: .whitespacesAndNewlines), !sandboxHome.isEmpty {
            do {
                try ensureSandboxDirectories(homePath: sandboxHome)
                accountService.sandboxHomeDirectory = sandboxHome
                accountService.sandboxMulticodexHomeDirectory = (sandboxHome as NSString).appendingPathComponent(".config/multicodex")
                return
            } catch {
                setAccountFeedback(message: nil, error: "Could not prepare temporary auth sandbox: \(error.localizedDescription)")
            }
        }

        isUsingTemporaryAuthSandbox = false
        preferences.temporaryAuthSandboxEnabled = false
        accountService.sandboxHomeDirectory = nil
        accountService.sandboxMulticodexHomeDirectory = nil
    }

    private func prepareFreshTemporaryAuthSandbox() throws -> String {
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("multicodex-test-\(UUID().uuidString)", isDirectory: true)
        try ensureSandboxDirectories(homePath: rootURL.path)
        return rootURL.path
    }

    private func ensureSandboxDirectories(homePath: String) throws {
        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let codexURL = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let multicodexURL = homeURL.appendingPathComponent(".config/multicodex", isDirectory: true)
        try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: codexURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: multicodexURL, withIntermediateDirectories: true)
    }

    private func syncSelectedSettingsAccount() {
        let candidates = filteredAccounts
        guard !candidates.isEmpty else {
            selectedSettingsAccountName = nil
            preferences.selectedSettingsAccountName = nil
            return
        }

        if let selectedSettingsAccountName,
           candidates.contains(where: { $0.name == selectedSettingsAccountName })
        {
            return
        }

        if let currentAccount,
           candidates.contains(where: { $0.name == currentAccount.name })
        {
            selectSettingsAccount(named: currentAccount.name)
            return
        }

        selectSettingsAccount(named: candidates.first?.name)
    }

    private func generateRandomAccountName() -> String {
        let existing = Set(accounts.map(\.name))
        for _ in 0..<20 {
            let random = UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            let candidate = "account-\(random.prefix(6))"
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "account-\(Int(Date().timeIntervalSince1970))"
    }
}
