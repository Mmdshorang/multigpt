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

    func shouldFallbackToTerminal(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("tty")
            || text.contains("not interactive")
            || text.contains("stdin")
            || text.contains("standard input")
    }

    func launchTerminalLoginFallback(accountName: String, createIfNeeded: Bool, rootError: Error) {
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
