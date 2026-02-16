import AppKit
import Foundation

@MainActor
final class UsageMenuViewModel: ObservableObject {
    @Published private(set) var profiles: [ProfileUsage] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshError: String?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var switchingProfileName: String?
    @Published private(set) var cliResolutionHint: String?
    @Published private(set) var profileActionInFlightName: String?
    @Published private(set) var profileActionMessage: String?
    @Published private(set) var profileActionError: String?
    @Published private(set) var runtimeProbeSummary: String?
    @Published private(set) var isCodexRuntimeAvailable = false
    @Published private(set) var focusedProfileName: String?
    @Published private(set) var isUsingTemporaryAuthSandbox = false
    @Published private(set) var temporaryAuthSandboxHome: String?
    @Published var customNodePath: String
    @Published var resetDisplayMode: ResetDisplayMode
    @Published private(set) var selectedSettingsSection: SettingsSection
    @Published private(set) var selectedSettingsProfileName: String?
    @Published private(set) var profileSearchQuery: String
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var isAdvancedSettingsVisible: Bool
    @Published private(set) var menuDensity: MenuDensity
    @Published private(set) var usageBarStyle: UsageBarStyle
    @Published private(set) var pendingProfileRemovalRequest: PendingProfileRemovalRequest?

    private let cli = MultiCodexCLI()
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let customNodePath = "multicodexMenu.customNodePath"
        static let legacyCustomExecutablePath = "multicodexMenu.customExecutablePath"
        static let resetDisplayMode = "multicodexMenu.resetDisplayMode"
        static let temporaryAuthSandboxEnabled = "multicodexMenu.temporaryAuthSandboxEnabled"
        static let temporaryAuthSandboxHome = "multicodexMenu.temporaryAuthSandboxHome"
        static let selectedSettingsSection = "multicodexMenu.selectedSettingsSection"
        static let selectedSettingsProfileName = "multicodexMenu.selectedSettingsProfileName"
        static let hasCompletedOnboarding = "multicodexMenu.hasCompletedOnboarding"
        static let isAdvancedSettingsVisible = "multicodexMenu.isAdvancedSettingsVisible"
        static let menuDensity = "multicodexMenu.menuDensity"
        static let usageBarStyle = "multicodexMenu.usageBarStyle"
    }
    private var refreshLoopTask: Task<Void, Never>?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var pendingInteractiveLoginProfile: String?
    private var feedbackAutoClearTask: Task<Void, Never>?

    init() {
        customNodePath =
            defaults.string(forKey: DefaultsKey.customNodePath)
            ?? defaults.string(forKey: DefaultsKey.legacyCustomExecutablePath)
            ?? ""
        let rawResetMode = defaults.string(forKey: DefaultsKey.resetDisplayMode)
        resetDisplayMode = ResetDisplayMode(rawValue: rawResetMode ?? "") ?? .relative
        selectedSettingsSection = SettingsSection(
            rawValue: defaults.string(forKey: DefaultsKey.selectedSettingsSection) ?? ""
        ) ?? .dashboard
        selectedSettingsProfileName = defaults.string(forKey: DefaultsKey.selectedSettingsProfileName)
        profileSearchQuery = ""
        hasCompletedOnboarding = defaults.bool(forKey: DefaultsKey.hasCompletedOnboarding)
        isAdvancedSettingsVisible = defaults.bool(forKey: DefaultsKey.isAdvancedSettingsVisible)
        menuDensity = MenuDensity(rawValue: defaults.string(forKey: DefaultsKey.menuDensity) ?? "") ?? .compact
        usageBarStyle = UsageBarStyle(rawValue: defaults.string(forKey: DefaultsKey.usageBarStyle) ?? "") ?? .depleting
        pendingProfileRemovalRequest = nil
        if !isAdvancedSettingsVisible, selectedSettingsSection == .advanced {
            selectedSettingsSection = .dashboard
        }
#if DEBUG
        isUsingTemporaryAuthSandbox = defaults.bool(forKey: DefaultsKey.temporaryAuthSandboxEnabled)
        temporaryAuthSandboxHome = defaults.string(forKey: DefaultsKey.temporaryAuthSandboxHome)
#else
        isUsingTemporaryAuthSandbox = false
        temporaryAuthSandboxHome = nil
#endif
        cli.customNodePath = customNodePath.isEmpty ? nil : customNodePath
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
        start()
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
        refreshLoopTask?.cancel()
    }

    var currentProfile: ProfileUsage? {
        profiles.first(where: { $0.isCurrent })
    }

    var menuBarTitle: String {
        guard let current = currentProfile else {
            return profiles.isEmpty ? "mcx" : "mcx ?"
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

        switch UsageLevel.from(usedPercent: currentProfile?.usage.fiveHour.usedPercent) {
        case .critical:
            return "flame.fill"
        case .warning:
            return "gauge.with.dots.needle.67percent"
        case .normal:
            return "person.2.circle"
        }
    }

    var currentFiveHourFraction: Double {
        currentProfile?.usage.fiveHour.normalizedFraction ?? 0
    }

    var currentWeeklyFraction: Double {
        currentProfile?.usage.weekly.normalizedFraction ?? 0
    }

    var lastUpdatedLabel: String {
        guard let lastUpdatedAt else {
            return "Not refreshed yet"
        }
        return "Updated \(UsageFormatter.relativeDateFormatter.localizedString(for: lastUpdatedAt, relativeTo: Date()))"
    }

    var profilesNeedingLogin: [ProfileUsage] {
        profiles.filter { $0.connectionState == .needsLogin }
    }

    var filteredProfiles: [ProfileUsage] {
        let query = profileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return profiles
        }

        return profiles.filter { profile in
            profile.name.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedSettingsProfile: ProfileUsage? {
        guard let selectedSettingsProfileName else {
            return nil
        }
        return filteredProfiles.first(where: { $0.name == selectedSettingsProfileName })
            ?? profiles.first(where: { $0.name == selectedSettingsProfileName })
    }

    var onboardingState: OnboardingState {
        if hasCompletedOnboarding {
            return OnboardingState(step: .done)
        }
        if !isCodexRuntimeAvailable {
            return OnboardingState(step: .runtime)
        }
        if profiles.isEmpty {
            return OnboardingState(step: .login)
        }
        if profiles.contains(where: { $0.connectionState != .connected }) {
            return OnboardingState(step: .verify)
        }
        return OnboardingState(step: .done)
    }

    var prioritizedMenuAlert: MenuAlertState? {
        if !isCodexRuntimeAvailable {
            return MenuAlertState(
                severity: .runtimeUnavailable,
                title: "Codex runtime unavailable",
                message: runtimeProbeSummary ?? "Set the runtime path in Settings.",
                actionTitle: "Open Runtime Settings",
                action: .openRuntimeSettings
            )
        }

        if let lastRefreshError {
            return MenuAlertState(
                severity: .refreshError,
                title: "Refresh failed",
                message: lastRefreshError,
                actionTitle: "Refresh Live",
                action: .refreshLive
            )
        }

        if let profile = profilesNeedingLogin.first {
            return MenuAlertState(
                severity: .authRequired,
                title: "Profile needs login",
                message: "\(profile.name) requires authentication.",
                actionTitle: "Re-login \(profile.name)",
                action: .relogin(profileName: profile.name)
            )
        }

        return nil
    }

    var preferredMenuProfileCount: Int {
        switch menuDensity {
        case .compact:
            return 5
        case .comfortable:
            return 4
        }
    }

    var settingsSections: [SettingsSection] {
        var sections: [SettingsSection] = [
            .dashboard,
            .profiles,
            .runtime,
            .display,
            .troubleshooting,
        ]
        if isAdvancedSettingsVisible {
            sections.append(.advanced)
        }
        return sections
    }

    func menuProfileRows(limit: Int? = nil) -> [ProfileRowState] {
        let maxCount = limit ?? preferredMenuProfileCount
        return Array(profiles.prefix(maxCount)).map { profile in
            ProfileRowState(profile: profile, resetDisplayMode: resetDisplayMode)
        }
    }

    func start() {
        guard refreshLoopTask == nil else {
            return
        }

        triggerRefresh(refreshLive: false)

        refreshLoopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(MultiCodexCLI.limitsCacheTTLSeconds))
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
        case let .relogin(profileName):
            openLoginInTerminal(for: profileName)
        }
    }

    func selectSettingsSection(_ section: SettingsSection) {
        if section == .advanced, !isAdvancedSettingsVisible {
            setAdvancedSettingsVisible(true)
        }
        selectedSettingsSection = section
        defaults.set(section.rawValue, forKey: DefaultsKey.selectedSettingsSection)
    }

    func selectSettingsProfile(named name: String?) {
        selectedSettingsProfileName = name
        if let name {
            defaults.set(name, forKey: DefaultsKey.selectedSettingsProfileName)
        } else {
            defaults.removeObject(forKey: DefaultsKey.selectedSettingsProfileName)
        }
    }

    func setProfileSearchQuery(_ query: String) {
        profileSearchQuery = query
        syncSelectedSettingsProfile()
    }

    func setAdvancedSettingsVisible(_ isVisible: Bool) {
        isAdvancedSettingsVisible = isVisible
        defaults.set(isVisible, forKey: DefaultsKey.isAdvancedSettingsVisible)
        if !isVisible, selectedSettingsSection == .advanced {
            selectSettingsSection(.dashboard)
        }
    }

    func setMenuDensity(_ density: MenuDensity) {
        guard density != menuDensity else {
            return
        }
        menuDensity = density
        defaults.set(density.rawValue, forKey: DefaultsKey.menuDensity)
    }

    func setUsageBarStyle(_ style: UsageBarStyle) {
        guard style != usageBarStyle else {
            return
        }
        usageBarStyle = style
        defaults.set(style.rawValue, forKey: DefaultsKey.usageBarStyle)
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
        defaults.set(true, forKey: DefaultsKey.hasCompletedOnboarding)
    }

    func resetOnboardingProgress() {
        hasCompletedOnboarding = false
        defaults.set(false, forKey: DefaultsKey.hasCompletedOnboarding)
    }

    func beginProfileRemoval(named name: String, deleteData: Bool) {
        pendingProfileRemovalRequest = PendingProfileRemovalRequest(profileName: name, deleteData: deleteData)
    }

    func cancelPendingProfileRemoval() {
        pendingProfileRemovalRequest = nil
    }

    func executePendingProfileRemoval(confirming typedName: String?) {
        guard let request = pendingProfileRemovalRequest else {
            return
        }

        if request.deleteData {
            let normalizedTyped = (typedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedTyped != request.profileName {
                setProfileFeedback(message: nil, error: "Type the profile name to confirm delete-data removal.")
                return
            }
        }

        pendingProfileRemovalRequest = nil
        removeProfile(named: request.profileName, deleteData: request.deleteData)
    }

    func switchToProfile(named name: String) {
        runSwitchAction(named: name) {
            try await self.cli.switchAccount(name: name)
            self.lastRefreshError = nil
            self.setProfileFeedback(message: "Now using \(name).", error: nil)
            await self.performRefresh(refreshLive: true)
        }
    }

    func startNewProfileLogin() {
        let generatedName = generateRandomProfileName()
        startLoginFlow(profileName: generatedName, createIfNeeded: true)
    }

    func renameProfile(from oldName: String, to rawNewName: String) {
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            profileActionError = "New profile name cannot be empty."
            profileActionMessage = nil
            return
        }

        guard oldName != newName else {
            profileActionError = nil
            profileActionMessage = "Profile name is unchanged."
            return
        }

        runProfileAction(for: oldName) {
            _ = try await self.cli.renameAccount(from: oldName, to: newName)
            if self.selectedSettingsProfileName == oldName {
                self.selectSettingsProfile(named: newName)
            }
            return .success("Renamed \(oldName) to \(newName).")
        }
    }

    func removeProfile(named name: String, deleteData: Bool) {
        if pendingProfileRemovalRequest?.profileName == name {
            pendingProfileRemovalRequest = nil
        }
        runProfileAction(for: name) {
            _ = try await self.cli.removeAccount(name: name, deleteData: deleteData)
            if self.selectedSettingsProfileName == name {
                self.selectSettingsProfile(named: nil)
            }
            return .success(deleteData ? "Removed \(name) and deleted stored data." : "Removed \(name).")
        }
    }

    func importCurrentAuth(into name: String) {
        runProfileAction(for: name) {
            _ = try await self.cli.importDefaultAuth(into: name)
            return .success("Imported current ~/.codex/auth.json into \(name).")
        }
    }

    func checkLoginStatus(for name: String) {
        runProfileAction(for: name) {
            let status = try await self.cli.fetchStatus(name: name)
            return self.statusOutcome(for: name, status: status, successFallback: "\(name): login status is OK.")
        }
    }

    func openLoginInTerminal(for name: String) {
        startLoginFlow(profileName: name, createIfNeeded: false)
    }

    func clearProfileActionFeedback() {
        feedbackAutoClearTask?.cancel()
        feedbackAutoClearTask = nil
        setProfileFeedback(message: nil, error: nil)
    }

    func toggleResetDisplayMode() {
        let nextMode = resetDisplayMode.next
        resetDisplayMode = nextMode
        defaults.set(nextMode.rawValue, forKey: DefaultsKey.resetDisplayMode)
    }

    func openMulticodexConfigDirectory() {
        let url = URL(fileURLWithPath: cli.effectiveMulticodexHomePath(), isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    func enableTemporaryAuthSandbox() {
        do {
            let sandboxHome = try prepareFreshTemporaryAuthSandbox()
            temporaryAuthSandboxHome = sandboxHome
            isUsingTemporaryAuthSandbox = true
            defaults.set(true, forKey: DefaultsKey.temporaryAuthSandboxEnabled)
            defaults.set(sandboxHome, forKey: DefaultsKey.temporaryAuthSandboxHome)
            configureSandboxEnvironment()
            setProfileFeedback(
                message: "Temporary auth sandbox enabled at \(sandboxHome).",
                error: nil
            )
            refreshLive()
        } catch {
            setProfileFeedback(message: nil, error: "Could not enable temporary auth sandbox: \(error.localizedDescription)")
        }
    }

    func resetTemporaryAuthSandbox() {
        enableTemporaryAuthSandbox()
    }

    func disableTemporaryAuthSandbox() {
        isUsingTemporaryAuthSandbox = false
        defaults.set(false, forKey: DefaultsKey.temporaryAuthSandboxEnabled)
        configureSandboxEnvironment()
        setProfileFeedback(message: "Temporary auth sandbox disabled. Using your regular setup.", error: nil)
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

    func updateCustomNodePath(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        customNodePath = trimmed
        if trimmed.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.customNodePath)
            defaults.removeObject(forKey: DefaultsKey.legacyCustomExecutablePath)
            cli.customNodePath = nil
        } else {
            defaults.set(trimmed, forKey: DefaultsKey.customNodePath)
            cli.customNodePath = trimmed
        }
        refreshRuntimeProbe()
        refresh()
    }

    func clearCustomNodePath() {
        updateCustomNodePath("")
    }

    func dismissFocusHint() {
        focusedProfileName = nil
    }

    func chooseCustomNodePath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Use"
        panel.message = "Choose the codex executable"

        if panel.runModal() == .OK, let path = panel.url?.path {
            updateCustomNodePath(path)
        }
    }

    private func performRefresh(refreshLive: Bool) async {
        if pendingInteractiveLoginProfile != nil {
            return
        }

        if isRefreshing {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let accounts = try await cli.fetchAccounts()
            let limits = try await cli.fetchLimits(refreshLive: refreshLive)

            profiles = UsageDataService.mergeProfiles(accounts: accounts, limits: limits)
            if let focused = focusedProfileName, !profiles.contains(where: { $0.name == focused }) {
                focusedProfileName = nil
            }
            syncSelectedSettingsProfile()
            if !hasCompletedOnboarding && onboardingState.step == .done {
                markOnboardingCompleted()
            }
            lastUpdatedAt = Date()
            cliResolutionHint = cli.resolutionHint

            if limits.errors.isEmpty {
                lastRefreshError = nil
            } else {
                let count = limits.errors.count
                let suffix = count == 1 ? "profile" : "profiles"
                lastRefreshError = "Usage fetch failed for \(count) \(suffix)."
            }
        } catch {
            lastRefreshError = error.localizedDescription
            cliResolutionHint = cli.resolutionHint
        }
    }

    private enum ProfileActionOutcome {
        case success(String)
        case failure(String)
    }

    private func setProfileFeedback(message: String?, error: String?) {
        profileActionMessage = message
        profileActionError = error
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
            profileActionMessage = nil
        }
    }

    private func triggerRefresh(refreshLive: Bool) {
        Task {
            await performRefresh(refreshLive: refreshLive)
        }
    }

    private func startLoginFlow(profileName: String, createIfNeeded: Bool) {
        guard profileActionInFlightName == nil, pendingInteractiveLoginProfile == nil else {
            return
        }

        Task {
            profileActionInFlightName = profileName
            focusedProfileName = profileName
            feedbackAutoClearTask?.cancel()
            feedbackAutoClearTask = nil
            profileActionMessage = "Opening browser login for \(profileName)..."
            profileActionError = nil

            defer {
                profileActionInFlightName = nil
            }

            do {
                _ = try await cli.loginInApp(account: profileName, createIfNeeded: createIfNeeded)
                _ = try await cli.importDefaultAuth(into: profileName)
                let status = try await cli.fetchStatus(name: profileName)

                switch statusOutcome(
                    for: profileName,
                    status: status,
                    successFallback: "Login synced to \(profileName)."
                ) {
                case let .success(message):
                    setProfileFeedback(message: message, error: nil)
                case let .failure(message):
                    setProfileFeedback(message: nil, error: message)
                }

                await performRefresh(refreshLive: true)
            } catch {
                if shouldFallbackToTerminal(error) {
                    launchTerminalLoginFallback(profileName: profileName, createIfNeeded: createIfNeeded, rootError: error)
                } else {
                    setProfileFeedback(message: nil, error: error.localizedDescription)
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

    private func launchTerminalLoginFallback(profileName: String, createIfNeeded: Bool, rootError: Error) {
        do {
            if createIfNeeded {
                try cli.openNewProfileLoginInTerminal(newProfileName: profileName)
            } else {
                try cli.openLoginInTerminal(account: profileName)
            }
            pendingInteractiveLoginProfile = profileName
            setProfileFeedback(
                message: "Using Terminal fallback for \(profileName). Complete login and return to MultiCodex.",
                error: nil
            )
        } catch {
            setProfileFeedback(
                message: nil,
                error: "\(rootError.localizedDescription) (Fallback failed: \(error.localizedDescription))"
            )
        }
    }

    private func statusOutcome(
        for profileName: String,
        status: AccountStatusPayload,
        successFallback: String
    ) -> ProfileActionOutcome {
        let summary = status.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if status.exitCode == 0 {
            return .success(summary.isEmpty ? successFallback : "\(profileName): \(summary)")
        }
        return .failure(summary.isEmpty ? "\(profileName): login check failed." : "\(profileName): \(summary)")
    }

    private func runProfileAction(
        for profileName: String,
        operation: @escaping () async throws -> ProfileActionOutcome
    ) {
        guard profileActionInFlightName == nil else {
            return
        }

        Task {
            profileActionInFlightName = profileName
            defer { profileActionInFlightName = nil }

            do {
                switch try await operation() {
                case let .success(message):
                    setProfileFeedback(message: message, error: nil)
                case let .failure(message):
                    setProfileFeedback(message: nil, error: message)
                }
                await performRefresh(refreshLive: false)
            } catch {
                setProfileFeedback(message: nil, error: error.localizedDescription)
            }
        }
    }

    private func runSwitchAction(
        named name: String,
        operation: @escaping () async throws -> Void
    ) {
        guard switchingProfileName == nil else {
            return
        }

        Task {
            switchingProfileName = name
            defer { switchingProfileName = nil }

            do {
                try await operation()
            } catch {
                lastRefreshError = error.localizedDescription
                cliResolutionHint = cli.resolutionHint
            }
        }
    }

    private func handleDidBecomeActive() {
        guard let pendingProfile = pendingInteractiveLoginProfile else {
            refreshLive()
            return
        }

        pendingInteractiveLoginProfile = nil
        focusedProfileName = pendingProfile
        runProfileAction(for: pendingProfile) {
            _ = try await self.cli.importDefaultAuth(into: pendingProfile)
            let status = try await self.cli.fetchStatus(name: pendingProfile)
            return self.statusOutcome(
                for: pendingProfile,
                status: status,
                successFallback: "Login synced to \(pendingProfile). You can rename it anytime."
            )
        }
    }

    private func refreshRuntimeProbe() {
        let probe = cli.probeRuntime()
        isCodexRuntimeAvailable = probe.isAvailable
        runtimeProbeSummary = probe.summary
    }

    private func configureSandboxEnvironment() {
        guard isUsingTemporaryAuthSandbox else {
            cli.sandboxHomeDirectory = nil
            cli.sandboxMulticodexHomeDirectory = nil
            return
        }

        if let sandboxHome = temporaryAuthSandboxHome?.trimmingCharacters(in: .whitespacesAndNewlines), !sandboxHome.isEmpty {
            do {
                try ensureSandboxDirectories(homePath: sandboxHome)
                cli.sandboxHomeDirectory = sandboxHome
                cli.sandboxMulticodexHomeDirectory = (sandboxHome as NSString).appendingPathComponent(".config/multicodex")
                return
            } catch {
                setProfileFeedback(message: nil, error: "Could not prepare temporary auth sandbox: \(error.localizedDescription)")
            }
        }

        isUsingTemporaryAuthSandbox = false
        defaults.set(false, forKey: DefaultsKey.temporaryAuthSandboxEnabled)
        cli.sandboxHomeDirectory = nil
        cli.sandboxMulticodexHomeDirectory = nil
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

    private func syncSelectedSettingsProfile() {
        let candidates = filteredProfiles
        guard !candidates.isEmpty else {
            selectedSettingsProfileName = nil
            defaults.removeObject(forKey: DefaultsKey.selectedSettingsProfileName)
            return
        }

        if let selectedSettingsProfileName,
           candidates.contains(where: { $0.name == selectedSettingsProfileName })
        {
            return
        }

        if let currentProfile,
           candidates.contains(where: { $0.name == currentProfile.name })
        {
            selectSettingsProfile(named: currentProfile.name)
            return
        }

        selectSettingsProfile(named: candidates.first?.name)
    }

    private func generateRandomProfileName() -> String {
        let existing = Set(profiles.map(\.name))
        for _ in 0..<20 {
            let random = UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            let candidate = "profile-\(random.prefix(6))"
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "profile-\(Int(Date().timeIntervalSince1970))"
    }
}
