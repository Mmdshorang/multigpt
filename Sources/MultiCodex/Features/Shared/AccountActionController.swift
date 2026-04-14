import Foundation

enum AccountActionOutcome {
    case success(String)
    case failure(String)
}

@MainActor
final class AccountActionController {
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
        guard viewModel.accountActionInFlightName == nil,
              viewModel.pendingInteractiveLoginSession?.phase != .waitingForExternalCompletion
        else {
            return
        }

        Task {
            viewModel.accountActionInFlightName = accountName
            viewModel.focusedAccountName = accountName
            viewModel.feedbackAutoClearTask?.cancel()
            viewModel.feedbackAutoClearTask = nil
            viewModel.accountActionMessage = "Opening browser login for \(accountName)..."
            viewModel.accountActionError = nil

            defer {
                viewModel.accountActionInFlightName = nil
            }

            do {
                let session = try self.makeInteractiveLoginSession(accountName: accountName, createIfNeeded: createIfNeeded)
                viewModel.pendingInteractiveLoginSession = nil
                _ = try await viewModel.accountService.loginInApp(
                    account: accountName,
                    createIfNeeded: createIfNeeded,
                    loginHome: session.loginSandboxHome
                )
                await self.completeInteractiveLogin(session: session, preserveFailedSession: false)
            } catch {
                if self.shouldFallbackToTerminal(error) {
                    self.launchTerminalLoginFallback(accountName: accountName, createIfNeeded: createIfNeeded, rootError: error)
                } else {
                    self.setAccountFeedback(message: nil, error: error.localizedDescription)
                }
            }
        }
    }

    func shouldFallbackToTerminal(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("tty")
            || text.contains("not interactive")
            || text.contains("stdin")
            || text.contains("standard input")
    }

    func launchTerminalLoginFallback(accountName: String, createIfNeeded: Bool, rootError: Error) {
        do {
            let session = try makeInteractiveLoginSession(accountName: accountName, createIfNeeded: createIfNeeded)
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
            setAccountFeedback(
                message: nil,
                error: "\(rootError.localizedDescription) (Fallback failed: \(error.localizedDescription))"
            )
        }
    }

    func resumePendingInteractiveLogin(_ session: PendingInteractiveLoginSession) {
        let viewModel = viewModel
        guard viewModel.accountActionInFlightName == nil else {
            return
        }

        Task {
            viewModel.accountActionInFlightName = session.accountName
            viewModel.focusedAccountName = session.accountName
            defer { viewModel.accountActionInFlightName = nil }

            await self.completeInteractiveLogin(session: session, preserveFailedSession: true)
        }
    }

    func completeInteractiveLogin(session: PendingInteractiveLoginSession, preserveFailedSession: Bool) async {
        do {
            let status = try await viewModel.accountService.fetchStatusForLoginHome(
                session.loginSandboxHome,
                accountName: session.accountName
            )

            guard status.exitCode == 0 else {
                if preserveFailedSession {
                    viewModel.pendingInteractiveLoginSession = session.withPhase(.needsRetry)
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
                return
            }

            _ = try await viewModel.accountService.importAuth(fromHome: session.loginSandboxHome, into: session.accountName)
            if session.shouldApplyAccountAuthOnSuccess {
                try await viewModel.accountService.switchAccount(name: session.accountName)
            }

            viewModel.pendingInteractiveLoginSession = nil
            let summary = status.output.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.upsertAuthenticatedAccountLocally(
                named: session.accountName,
                currentAccountName: session.shouldApplyAccountAuthOnSuccess ? session.accountName : nil,
                lastLoginStatus: summary.isEmpty ? nil : summary
            )
            switch statusOutcome(
                for: session.accountName,
                status: status,
                successFallback: session.successFallback
            ) {
            case let .success(message):
                setAccountFeedback(message: message, error: nil)
            case let .failure(message):
                setAccountFeedback(message: nil, error: message)
            }

            Task { @MainActor in
                await viewModel.refreshController.performRefresh(refreshLive: true, allowAutoSwitch: false)
            }
        } catch {
            if preserveFailedSession {
                viewModel.pendingInteractiveLoginSession = session.withPhase(.needsRetry)
                setAccountFeedback(
                    message: nil,
                    error: "\(error.localizedDescription) Return to Terminal/browser and retry the login flow."
                )
            } else {
                viewModel.pendingInteractiveLoginSession = nil
                setAccountFeedback(message: nil, error: error.localizedDescription)
            }
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
                Task { @MainActor in
                    await viewModel.refreshController.performRefresh(refreshLive: false)
                }
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
        let rootURL = viewModel.fileManager.temporaryDirectory
            .appendingPathComponent("multicodex-login-\(UUID().uuidString)", isDirectory: true)
        let homeURL = URL(fileURLWithPath: rootURL.path, isDirectory: true)
        let codexURL = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let multicodexURL = homeURL.appendingPathComponent(".config/multicodex", isDirectory: true)
        try viewModel.fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try viewModel.fileManager.createDirectory(at: codexURL, withIntermediateDirectories: true)
        try viewModel.fileManager.createDirectory(at: multicodexURL, withIntermediateDirectories: true)
        return rootURL.path
    }
}
