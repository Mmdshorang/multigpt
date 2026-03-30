import Foundation

private enum AccountActionCoordinator {}

extension AccountsMenuViewModel {
    enum AccountActionOutcome {
        case success(String)
        case failure(String)
    }

    func setAccountFeedback(message: String?, error: String?) {
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

    func startLoginFlow(accountName: String, createIfNeeded: Bool) {
        guard accountActionInFlightName == nil,
              pendingInteractiveLoginSession?.phase != .waitingForExternalCompletion
        else {
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
                let session = try makeInteractiveLoginSession(accountName: accountName, createIfNeeded: createIfNeeded)
                pendingInteractiveLoginSession = nil
                _ = try await accountService.loginInApp(
                    account: accountName,
                    createIfNeeded: createIfNeeded,
                    loginHome: session.loginSandboxHome
                )
                await completeInteractiveLogin(session: session, preserveFailedSession: false)
            } catch {
                if shouldFallbackToTerminal(error) {
                    launchTerminalLoginFallback(accountName: accountName, createIfNeeded: createIfNeeded, rootError: error)
                } else {
                    setAccountFeedback(message: nil, error: error.localizedDescription)
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
                try accountService.openNewAccountLoginInTerminal(
                    newAccountName: accountName,
                    loginHome: session.loginSandboxHome
                )
            } else {
                try accountService.openLoginInTerminal(account: accountName, loginHome: session.loginSandboxHome)
            }
            pendingInteractiveLoginSession = session
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

    func makeInteractiveLoginSession(accountName: String, createIfNeeded: Bool) throws -> PendingInteractiveLoginSession {
        let sandboxHome = try prepareFreshTemporaryAuthSandbox()
        let wasCurrentAccount = currentAccount?.name == accountName
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

    func resumePendingInteractiveLogin(_ session: PendingInteractiveLoginSession) {
        guard accountActionInFlightName == nil else {
            return
        }

        Task {
            accountActionInFlightName = session.accountName
            focusedAccountName = session.accountName
            defer { accountActionInFlightName = nil }

            await completeInteractiveLogin(session: session, preserveFailedSession: true)
        }
    }

    func completeInteractiveLogin(session: PendingInteractiveLoginSession, preserveFailedSession: Bool) async {
        do {
            let status = try await accountService.fetchStatusForLoginHome(
                session.loginSandboxHome,
                accountName: session.accountName
            )

            guard status.exitCode == 0 else {
                if preserveFailedSession {
                    pendingInteractiveLoginSession = session.withPhase(.needsRetry)
                } else {
                    pendingInteractiveLoginSession = nil
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

            _ = try await accountService.importAuth(fromHome: session.loginSandboxHome, into: session.accountName)
            if session.shouldApplyAccountAuthOnSuccess {
                try await accountService.switchAccount(name: session.accountName)
            }

            pendingInteractiveLoginSession = nil
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

            await performRefresh(refreshLive: true, allowAutoSwitch: false)
        } catch {
            if preserveFailedSession {
                pendingInteractiveLoginSession = session.withPhase(.needsRetry)
                setAccountFeedback(
                    message: nil,
                    error: "\(error.localizedDescription) Return to Terminal/browser and retry the login flow."
                )
            } else {
                pendingInteractiveLoginSession = nil
                setAccountFeedback(message: nil, error: error.localizedDescription)
            }
        }
    }

    func statusOutcome(
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

    func runAccountAction(
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

}
