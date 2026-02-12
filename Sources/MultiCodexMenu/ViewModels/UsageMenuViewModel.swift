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
    @Published private(set) var isUsingTemporaryAuthSandbox = false
    @Published private(set) var temporaryAuthSandboxHome: String?
    @Published var customNodePath: String
    @Published var resetDisplayMode: ResetDisplayMode

    private let cli = MultiCodexCLI()
    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let customNodePath = "multicodexMenu.customNodePath"
        static let legacyCustomExecutablePath = "multicodexMenu.customExecutablePath"
        static let resetDisplayMode = "multicodexMenu.resetDisplayMode"
        static let temporaryAuthSandboxEnabled = "multicodexMenu.temporaryAuthSandboxEnabled"
        static let temporaryAuthSandboxHome = "multicodexMenu.temporaryAuthSandboxHome"
    }
    private var refreshLoopTask: Task<Void, Never>?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var pendingInteractiveLoginProfile: String?

    init() {
        customNodePath =
            defaults.string(forKey: DefaultsKey.customNodePath)
            ?? defaults.string(forKey: DefaultsKey.legacyCustomExecutablePath)
            ?? ""
        let rawResetMode = defaults.string(forKey: DefaultsKey.resetDisplayMode)
        resetDisplayMode = ResetDisplayMode(rawValue: rawResetMode ?? "") ?? .relative
        isUsingTemporaryAuthSandbox = defaults.bool(forKey: DefaultsKey.temporaryAuthSandboxEnabled)
        temporaryAuthSandboxHome = defaults.string(forKey: DefaultsKey.temporaryAuthSandboxHome)
        cli.customNodePath = customNodePath.isEmpty ? nil : customNodePath
        configureSandboxEnvironment()
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

    var subtitle: String {
        if let current = currentProfile {
            return "Current profile: \(current.name)"
        }
        return "No current profile selected"
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
        beginInteractiveLogin(
            profileName: generatedName,
            successMessage: "Opened browser login. After sign-in, profile \(generatedName) will appear (you can rename it anytime)."
        ) {
            try self.cli.openNewProfileLoginInTerminal(newProfileName: generatedName)
        }
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
            return .success("Renamed \(oldName) to \(newName).")
        }
    }

    func removeProfile(named name: String, deleteData: Bool) {
        runProfileAction(for: name) {
            _ = try await self.cli.removeAccount(name: name, deleteData: deleteData)
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
        beginInteractiveLogin(
            profileName: name,
            successMessage: "Opened Terminal login for \(name). Browser login should start and return you to MultiCodex."
        ) {
            try self.cli.openLoginInTerminal(account: name)
        }
    }

    func clearProfileActionFeedback() {
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
        refresh()
    }

    func clearCustomNodePath() {
        updateCustomNodePath("")
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
    }

    private func triggerRefresh(refreshLive: Bool) {
        Task {
            await performRefresh(refreshLive: refreshLive)
        }
    }

    private func beginInteractiveLogin(
        profileName: String,
        successMessage: String,
        openFlow: () throws -> Void
    ) {
        guard profileActionInFlightName == nil else {
            return
        }

        do {
            try openFlow()
            pendingInteractiveLoginProfile = profileName
            setProfileFeedback(message: successMessage, error: nil)
        } catch {
            pendingInteractiveLoginProfile = nil
            setProfileFeedback(message: nil, error: error.localizedDescription)
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
