import Foundation

enum AccountActionOutcome {
    case success(String)
    case failure(String)
}

@MainActor
final class AccountActionController {
    struct InteractiveLoginOutcome {
        let success: Bool
        let effectiveAccountName: String
        let message: String?
        let error: String?
    }

    unowned let viewModel: AccountsMenuViewModel

    init(viewModel: AccountsMenuViewModel) {
        self.viewModel = viewModel
    }

    func setAccountFeedback(message: String?, error: String?) {
        let viewModel = viewModel
        viewModel.accountActionMessage = message
        viewModel.accountActionError = error
        viewModel.feedbackAutoClearTask?.cancel()
        viewModel.feedbackAutoClearTask = nil
        guard message != nil else {
            return
        }
        viewModel.feedbackAutoClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled {
                return
            }
            viewModel.accountActionMessage = nil
        }
    }

    func startLoginFlow(accountName: String, createIfNeeded: Bool) {
        let viewModel = viewModel
        guard viewModel.loginInFlightName == nil else {
            return
        }
        if let pendingSession = viewModel.pendingInteractiveLoginSession,
           pendingSession.phase == .waitingForExternalCompletion
        {
            guard pendingSession.accountName == accountName,
                  pendingSession.createIfNeeded == createIfNeeded
            else {
                setAccountFeedback(
                    message: nil,
                    error: "Finish login for \(pendingSession.accountName) before starting another login."
                )
                return
            }
            removeLoginSandboxIfPossible(pendingSession.loginSandboxHome)
            viewModel.pendingInteractiveLoginSession = nil
        }

        let loginTask = Task {
            viewModel.loginInFlightName = accountName
            viewModel.focusedAccountName = accountName
            viewModel.feedbackAutoClearTask?.cancel()
            viewModel.feedbackAutoClearTask = nil
            viewModel.accountActionMessage = "Opening browser login for \(accountName)..."
            viewModel.accountActionError = nil

            var sessionToCleanup: PendingInteractiveLoginSession?
            defer {
                viewModel.activeLoginTask = nil
                viewModel.activeLoginSession = nil
                viewModel.loginInFlightName = nil
                if let sessionToCleanup {
                    self.removeLoginSandboxIfPossible(sessionToCleanup.loginSandboxHome)
                }
            }

            do {
                let session = try self.makeInteractiveLoginSession(accountName: accountName, createIfNeeded: createIfNeeded)
                sessionToCleanup = session
                viewModel.activeLoginSession = session
                viewModel.pendingInteractiveLoginSession = nil
                _ = try await viewModel.accountService.loginInApp(
                    account: accountName,
                    createIfNeeded: createIfNeeded,
                    loginHome: session.loginSandboxHome
                )
                _ = await self.completeInteractiveLogin(session: session, preserveFailedSession: false)
                sessionToCleanup = nil
            } catch is CancellationError {
                viewModel.pendingInteractiveLoginSession = nil
                if let session = sessionToCleanup, session.createIfNeeded {
                    await self.removeCreatedLoginAccount(session)
                }
                self.setAccountFeedback(message: "Cancelled login for \(accountName).", error: nil)
            } catch {
                if self.shouldFallbackToTerminal(error) {
                    self.launchTerminalLoginFallback(accountName: accountName, createIfNeeded: createIfNeeded, rootError: error)
                } else {
                    self.setAccountFeedback(message: nil, error: error.localizedDescription)
                }
            }
        }
        viewModel.activeLoginTask = loginTask
    }

    func shouldFallbackToTerminal(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("tty")
            || text.contains("not interactive")
            || text.contains("stdin")
            || text.contains("standard input")
    }

    func launchTerminalLoginFallback(accountName: String, createIfNeeded: Bool, rootError: Error) {
        beginTerminalLoginFlow(accountName: accountName, createIfNeeded: createIfNeeded, rootError: rootError)
    }

    func startTerminalLoginFlow(accountName: String, createIfNeeded: Bool) {
        let viewModel = viewModel
        guard viewModel.loginInFlightName == nil else {
            return
        }
        if let pendingSession = viewModel.pendingInteractiveLoginSession,
           pendingSession.phase == .waitingForExternalCompletion
        {
            guard pendingSession.accountName == accountName,
                  pendingSession.createIfNeeded == createIfNeeded
            else {
                setAccountFeedback(
                    message: nil,
                    error: "Finish login for \(pendingSession.accountName) before starting another login."
                )
                return
            }
            setAccountFeedback(
                message: "Login already in progress for \(accountName). Continue in the existing browser or Terminal window.",
                error: nil
            )
            return
        }
        beginTerminalLoginFlow(accountName: accountName, createIfNeeded: createIfNeeded, rootError: nil)
    }

    private func beginTerminalLoginFlow(accountName: String, createIfNeeded: Bool, rootError: Error?) {
        var sessionHomeToCleanup: String?
        do {
            let session = try makeInteractiveLoginSession(accountName: accountName, createIfNeeded: createIfNeeded)
            sessionHomeToCleanup = session.loginSandboxHome
            if createIfNeeded {
                try viewModel.accountService.openNewAccountLoginInTerminal(
                    newAccountName: accountName,
                    loginHome: session.loginSandboxHome
                )
            } else {
                try viewModel.accountService.openLoginInTerminal(account: accountName, loginHome: session.loginSandboxHome)
            }
            viewModel.pendingInteractiveLoginSession = session
            setAccountFeedback(
                message: "Using Terminal fallback for \(accountName). Complete login and return to MultiCodex.",
                error: nil
            )
        } catch {
            if let sessionHomeToCleanup {
                removeLoginSandboxIfPossible(sessionHomeToCleanup)
            }
            if let rootError {
                setAccountFeedback(
                    message: nil,
                    error: "\(rootError.localizedDescription) (Fallback failed: \(error.localizedDescription))"
                )
            } else {
                setAccountFeedback(message: nil, error: error.localizedDescription)
            }
        }
    }

    func resumePendingInteractiveLogin(_ session: PendingInteractiveLoginSession) {
        let viewModel = viewModel
        guard viewModel.loginInFlightName == nil else {
            return
        }

        Task {
            viewModel.loginInFlightName = session.accountName
            viewModel.focusedAccountName = session.accountName
            defer { viewModel.loginInFlightName = nil }

            _ = await self.completeInteractiveLogin(session: session, preserveFailedSession: true)
        }
    }

    func abortPendingLogin() {
        guard let session = viewModel.pendingInteractiveLoginSession,
              viewModel.loginInFlightName == nil
        else {
            return
        }

        viewModel.pendingInteractiveLoginSession = nil
        removeLoginSandboxIfPossible(session.loginSandboxHome)
        setAccountFeedback(message: "Aborted login for \(session.accountName).", error: nil)
    }

    func cancelLogin() {
        if viewModel.loginInFlightName != nil {
            viewModel.activeLoginTask?.cancel()
            return
        }

        abortPendingLogin()
    }

    func cancelLogin(for accountName: String, removeCreatedAccount: Bool) {
        if viewModel.activeLoginSession?.accountName == accountName {
            viewModel.activeLoginTask?.cancel()
            return
        }

        guard let session = viewModel.pendingInteractiveLoginSession,
              session.accountName == accountName,
              viewModel.loginInFlightName == nil
        else {
            return
        }

        viewModel.pendingInteractiveLoginSession = nil
        removeLoginSandboxIfPossible(session.loginSandboxHome)

        guard removeCreatedAccount, session.createIfNeeded else {
            setAccountFeedback(message: "Cancelled login for \(session.accountName).", error: nil)
            return
        }

        Task {
            await removeCreatedLoginAccount(session)
            setAccountFeedback(
                message: "Cancelled login for \(session.accountName) and removed the account.",
                error: nil
            )
        }
    }

    func prepareSequentialNewAccountLogin(accountNames: [String]) {
        guard !accountNames.isEmpty else {
            setAccountFeedback(message: nil, error: "Choose at least one account.")
            return
        }
        guard viewModel.sequentialLoginState?.isRunning != true else {
            return
        }

        viewModel.sequentialLoginTask?.cancel()
        viewModel.sequentialLoginTask = nil
        let items = accountNames.map { SequentialLoginItem(accountName: $0) }
        viewModel.sequentialLoginState = SequentialLoginState(items: items)
        setAccountFeedback(
            message: "Prepared batch login for \(items.count) account\(items.count == 1 ? "" : "s").",
            error: nil
        )
    }

    func startSequentialNewAccountLogin() {
        guard var state = viewModel.sequentialLoginState,
              !state.items.isEmpty,
              !state.isRunning,
              viewModel.loginInFlightName == nil,
              viewModel.switchingAccountName == nil,
              viewModel.pendingInteractiveLoginSession?.phase != .waitingForExternalCompletion
        else {
            return
        }

        state.isRunning = true
        state.cancellationRequested = false
        state.currentIndex = nil
        state.startedAt = Date()
        state.finishedAt = nil
        state.items = state.items.map { item in
            var next = item
            next.status = .pending
            next.message = nil
            next.didCleanup = false
            next.resolvedAccountName = nil
            return next
        }
        viewModel.sequentialLoginState = state
        viewModel.sequentialLoginTask?.cancel()
        viewModel.sequentialLoginTask = Task { @MainActor [weak self] in
            await self?.runSequentialLogin()
        }
    }

    func cancelSequentialNewAccountLogin() {
        guard var state = viewModel.sequentialLoginState, state.isRunning else {
            return
        }
        state.cancellationRequested = true
        viewModel.sequentialLoginState = state
        viewModel.sequentialLoginTask?.cancel()
        setAccountFeedback(
            message: "Stopping batch login after current step and cleaning up unfinished accounts...",
            error: nil
        )
    }

    func retryFailedSequentialNewAccountLogin() {
        guard let state = viewModel.sequentialLoginState, !state.isRunning else {
            return
        }

        let failedNames = state.items
            .filter { $0.status == .failed }
            .map(\.accountName)

        guard !failedNames.isEmpty else {
            setAccountFeedback(message: nil, error: "No failed accounts to retry.")
            return
        }

        prepareSequentialNewAccountLogin(accountNames: failedNames)
        startSequentialNewAccountLogin()
    }

    func completeInteractiveLogin(session: PendingInteractiveLoginSession, preserveFailedSession: Bool) async -> InteractiveLoginOutcome {
        var retainSandboxHome = false
        defer {
            if !retainSandboxHome {
                removeLoginSandboxIfPossible(session.loginSandboxHome)
            }
        }

        do {
            let status = try await viewModel.accountService.fetchStatusForLoginHome(
                session.loginSandboxHome,
                accountName: session.accountName
            )

            guard status.exitCode == 0 else {
                if preserveFailedSession {
                    viewModel.pendingInteractiveLoginSession = session.withPhase(.needsRetry)
                    retainSandboxHome = true
                } else {
                    viewModel.pendingInteractiveLoginSession = nil
                }

                switch statusOutcome(
                    for: session.accountName,
                    status: status,
                    successFallback: session.successFallback
                ) {
                case let .success(message):
                    setAccountFeedback(message: message, error: nil)
                case let .failure(message):
                    setAccountFeedback(
                        message: nil,
                        error: preserveFailedSession
                            ? "\(message) Return to Terminal/browser and retry the login flow."
                            : message
                    )
                }
                return InteractiveLoginOutcome(
                    success: false,
                    effectiveAccountName: session.accountName,
                    message: nil,
                    error: status.output.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            try await viewModel.runAuthMutation(named: session.accountName) { [self] in
                _ = try await viewModel.accountService.importAuth(fromHome: session.loginSandboxHome, into: session.accountName)
                if session.shouldApplyAccountAuthOnSuccess {
                    try await viewModel.accountService.switchAccount(name: session.accountName)
                }
            }

            var effectiveAccountName = session.accountName
            var renameNote: String?
            if session.createIfNeeded,
               let preferredName = await suggestedAccountNameForNewLogin(session: session),
               preferredName != session.accountName
            {
                do {
                    _ = try await viewModel.accountService.renameAccount(from: session.accountName, to: preferredName)
                    viewModel.renameAccountLocally(from: session.accountName, to: preferredName)
                    if viewModel.selectedSettingsAccountName == session.accountName {
                        viewModel.settingsController.selectSettingsAccount(named: preferredName)
                    }
                    effectiveAccountName = preferredName
                    renameNote = "Saved as \(preferredName)."
                } catch {
                    renameNote = nil
                }
            }

            viewModel.pendingInteractiveLoginSession = nil
            let summary = status.output.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.upsertAuthenticatedAccountLocally(
                named: effectiveAccountName,
                currentAccountName: session.shouldApplyAccountAuthOnSuccess ? effectiveAccountName : nil,
                lastLoginStatus: summary.isEmpty ? nil : summary
            )

            let successFallback: String
            if session.shouldApplyAccountAuthOnSuccess {
                successFallback = "Login synced to \(effectiveAccountName)."
            } else if session.createIfNeeded {
                successFallback = "Saved login to \(effectiveAccountName). Switch when you want to use it."
            } else {
                successFallback = "Updated stored login for \(effectiveAccountName)."
            }

            switch statusOutcome(
                for: effectiveAccountName,
                status: status,
                successFallback: successFallback
            ) {
            case let .success(message):
                let fullMessage: String
                if let renameNote {
                    fullMessage = "\(message) \(renameNote)"
                    setAccountFeedback(message: fullMessage, error: nil)
                } else {
                    fullMessage = message
                    setAccountFeedback(message: message, error: nil)
                }

                viewModel.refreshController.triggerRefresh(refreshLive: true, allowAutoSwitch: false)

                return InteractiveLoginOutcome(
                    success: true,
                    effectiveAccountName: effectiveAccountName,
                    message: fullMessage,
                    error: nil
                )
            case let .failure(message):
                setAccountFeedback(message: nil, error: message)
                return InteractiveLoginOutcome(
                    success: false,
                    effectiveAccountName: effectiveAccountName,
                    message: nil,
                    error: message
                )
            }
        } catch {
            if preserveFailedSession {
                viewModel.pendingInteractiveLoginSession = session.withPhase(.needsRetry)
                retainSandboxHome = true
                setAccountFeedback(
                    message: nil,
                    error: "\(error.localizedDescription) Return to Terminal/browser and retry the login flow."
                )
            } else {
                viewModel.pendingInteractiveLoginSession = nil
                setAccountFeedback(message: nil, error: error.localizedDescription)
            }
            return InteractiveLoginOutcome(
                success: false,
                effectiveAccountName: session.accountName,
                message: nil,
                error: error.localizedDescription
            )
        }
    }

    private func suggestedAccountNameForNewLogin(session: PendingInteractiveLoginSession) async -> String? {
        let currentName = session.accountName
        guard let preferredName = viewModel.accountService
            .inferDefaultWorkspaceEmail(fromLoginHome: session.loginSandboxHome)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !preferredName.isEmpty
        else {
            return nil
        }

        let existingNames = Set(
            (try? await viewModel.accountService.fetchAccounts())?.accounts.map(\.name)
                ?? viewModel.accounts.map(\.name)
        )
        return uniqueName(base: preferredName, currentName: currentName, existingNames: existingNames)
    }

    private func uniqueName(base: String, currentName: String, existingNames: Set<String>) -> String {
        if base == currentName || !existingNames.contains(base) {
            return base
        }

        for index in 2...99 {
            let candidate = "\(base)-\(index)"
            if !existingNames.contains(candidate) {
                return candidate
            }
        }

        return "\(base)-\(Int(Date().timeIntervalSince1970))"
    }

    private func removeCreatedLoginAccount(_ session: PendingInteractiveLoginSession) async {
        guard session.createIfNeeded else {
            return
        }

        do {
            let payload = try await viewModel.accountService.removeAccount(name: session.accountName, deleteData: true)
            viewModel.removeAccountLocally(named: session.accountName, currentAccountName: payload.currentAccount)
        } catch {
            setAccountFeedback(message: nil, error: "Cancelled login, but removing \(session.accountName) failed: \(error.localizedDescription)")
        }
    }

    func runAccountAction(
        for accountName: String,
        operation: @escaping () async throws -> AccountActionOutcome
    ) {
        let viewModel = viewModel
        guard viewModel.accountActionInFlightName == nil else {
            return
        }

        Task {
            viewModel.accountActionInFlightName = accountName
            var shouldRefresh = false
            do {
                switch try await operation() {
                case let .success(message):
                    self.setAccountFeedback(message: message, error: nil)
                case let .failure(message):
                    self.setAccountFeedback(message: nil, error: message)
                }
                shouldRefresh = true
            } catch {
                self.setAccountFeedback(message: nil, error: error.localizedDescription)
            }

            viewModel.accountActionInFlightName = nil

            if shouldRefresh {
                viewModel.refreshController.triggerRefresh(refreshLive: false)
            }
        }
    }

    private func makeInteractiveLoginSession(accountName: String, createIfNeeded: Bool) throws -> PendingInteractiveLoginSession {
        let sandboxHome = try prepareFreshLoginSandbox()
        let wasCurrentAccount = viewModel.currentAccount?.name == accountName
        let successFallback: String
        if wasCurrentAccount {
            successFallback = "Login synced to \(accountName)."
        } else if createIfNeeded {
            successFallback = "Saved login to \(accountName). Switch when you want to use it."
        } else {
            successFallback = "Updated stored login for \(accountName)."
        }

        return PendingInteractiveLoginSession(
            accountName: accountName,
            loginSandboxHome: sandboxHome,
            shouldApplyAccountAuthOnSuccess: wasCurrentAccount,
            successFallback: successFallback,
            createIfNeeded: createIfNeeded,
            phase: .waitingForExternalCompletion
        )
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

    private func prepareFreshLoginSandbox() throws -> String {
        let rootURL = try prepareLoginSandboxRootDirectory()
            .appendingPathComponent("session-\(UUID().uuidString)", isDirectory: true)
        let homeURL = URL(fileURLWithPath: rootURL.path, isDirectory: true)
        let codexURL = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let multicodexURL = homeURL.appendingPathComponent(".config/multicodex", isDirectory: true)
        try viewModel.fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try viewModel.fileManager.createDirectory(at: codexURL, withIntermediateDirectories: true)
        try viewModel.fileManager.createDirectory(at: multicodexURL, withIntermediateDirectories: true)
        return rootURL.path
    }

    private func prepareLoginSandboxRootDirectory() throws -> URL {
        let root = viewModel.fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".multicodex", isDirectory: true)
            .appendingPathComponent("login-sandboxes", isDirectory: true)
        try viewModel.fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func runSequentialLogin() async {
        guard let total = viewModel.sequentialLoginState?.items.count else {
            return
        }

        for index in 0..<total {
            if Task.isCancelled {
                break
            }
            await runSequentialLoginItem(at: index)
        }

        await finishSequentialLogin(cancelled: Task.isCancelled)
    }

    private func runSequentialLoginItem(at index: Int) async {
        guard var state = viewModel.sequentialLoginState,
              index < state.items.count,
              state.isRunning
        else {
            return
        }

        var item = state.items[index]
        item.status = .inProgress
        item.message = nil
        state.currentIndex = index
        state.items[index] = item
        viewModel.sequentialLoginState = state

        let outcome = await runSingleSequentialNewLogin(accountName: item.accountName)
        guard var latestState = viewModel.sequentialLoginState, index < latestState.items.count else {
            return
        }

        latestState.items[index].resolvedAccountName = outcome.success ? outcome.effectiveAccountName : nil
        latestState.items[index].status = outcome.success ? .success : .failed
        latestState.items[index].message = outcome.success ? outcome.message : outcome.error
        latestState.currentIndex = nil
        viewModel.sequentialLoginState = latestState

        if !outcome.success {
            await cleanupSequentialAccount(at: index, reason: "Removed incomplete account.")
        }
    }

    private func runSingleSequentialNewLogin(accountName: String) async -> InteractiveLoginOutcome {
        viewModel.accountActionInFlightName = accountName
        viewModel.focusedAccountName = accountName
        viewModel.feedbackAutoClearTask?.cancel()
        viewModel.feedbackAutoClearTask = nil
        viewModel.accountActionMessage = "Starting login for \(accountName)..."
        viewModel.accountActionError = nil
        var transientSandboxHome: String?
        defer {
            if let transientSandboxHome {
                removeLoginSandboxIfPossible(transientSandboxHome)
            }
            viewModel.accountActionInFlightName = nil
        }

        do {
            let session = try makeInteractiveLoginSession(accountName: accountName, createIfNeeded: true)
            transientSandboxHome = session.loginSandboxHome
            viewModel.pendingInteractiveLoginSession = nil
            _ = try await viewModel.accountService.loginInApp(
                account: accountName,
                createIfNeeded: true,
                loginHome: session.loginSandboxHome
            )
            let outcome = await completeInteractiveLogin(session: session, preserveFailedSession: false)
            transientSandboxHome = nil
            return outcome
        } catch {
            viewModel.pendingInteractiveLoginSession = nil
            if shouldFallbackToTerminal(error) {
                let message = "\(accountName): requires terminal login in this environment. Skipping."
                setAccountFeedback(message: nil, error: message)
                return InteractiveLoginOutcome(
                    success: false,
                    effectiveAccountName: accountName,
                    message: nil,
                    error: message
                )
            }

            let message = "\(accountName): \(error.localizedDescription)"
            setAccountFeedback(message: nil, error: message)
            return InteractiveLoginOutcome(
                success: false,
                effectiveAccountName: accountName,
                message: nil,
                error: message
            )
        }
    }

    private func finishSequentialLogin(cancelled: Bool) async {
        viewModel.sequentialLoginTask = nil
        guard var state = viewModel.sequentialLoginState else {
            return
        }

        if cancelled {
            for index in state.items.indices where state.items[index].status == .pending || state.items[index].status == .inProgress {
                state.items[index].status = .cancelled
                if state.items[index].message == nil {
                    state.items[index].message = "Cancelled."
                }
            }
        }

        viewModel.sequentialLoginState = state
        await cleanupIncompleteSequentialAccounts()

        guard var latest = viewModel.sequentialLoginState else {
            return
        }
        latest.isRunning = false
        latest.cancellationRequested = false
        latest.currentIndex = nil
        latest.finishedAt = Date()
        viewModel.sequentialLoginState = latest

        if cancelled {
            setAccountFeedback(
                message: "Batch login cancelled. Completed \(latest.completedCount)/\(latest.totalCount). Cleaned up incomplete accounts.",
                error: nil
            )
            return
        }

        setAccountFeedback(
            message: "Batch login finished. \(latest.successCount) succeeded, \(latest.failedCount) failed, \(latest.cancelledCount) cancelled.",
            error: nil
        )
    }

    private func cleanupIncompleteSequentialAccounts() async {
        guard let state = viewModel.sequentialLoginState else {
            return
        }

        for index in state.items.indices {
            let item = state.items[index]
            guard item.status != .success, !item.didCleanup else {
                continue
            }
            await cleanupSequentialAccount(at: index, reason: "Removed incomplete account.")
        }
    }

    private func cleanupSequentialAccount(at index: Int, reason: String) async {
        guard var state = viewModel.sequentialLoginState,
              index < state.items.count,
              !state.items[index].didCleanup
        else {
            return
        }

        let accountName = state.items[index].accountName

        do {
            let payload = try await viewModel.accountService.removeAccount(name: accountName, deleteData: true)
            viewModel.removeAccountLocally(named: accountName, currentAccountName: payload.currentAccount)
            state = viewModel.sequentialLoginState ?? state
            guard index < state.items.count else { return }
            state.items[index].didCleanup = true
            let existing = state.items[index].message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing, !existing.isEmpty {
                state.items[index].message = "\(existing) \(reason)"
            } else {
                state.items[index].message = reason
            }
            viewModel.sequentialLoginState = state
        } catch {
            state = viewModel.sequentialLoginState ?? state
            guard index < state.items.count else { return }
            let cleanupError = "Cleanup failed: \(error.localizedDescription)"
            let existing = state.items[index].message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing, !existing.isEmpty {
                state.items[index].message = "\(existing) \(cleanupError)"
            } else {
                state.items[index].message = cleanupError
            }
            viewModel.sequentialLoginState = state
        }
    }

    private func removeLoginSandboxIfPossible(_ homePath: String) {
        guard !homePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        do {
            if viewModel.fileManager.fileExists(atPath: homePath) {
                try viewModel.fileManager.removeItem(atPath: homePath)
            }
        } catch {
            // Best-effort cleanup only; login result should not be blocked by cleanup failure.
        }
    }
}
