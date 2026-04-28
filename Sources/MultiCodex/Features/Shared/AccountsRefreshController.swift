import Foundation

@MainActor
final class AccountsRefreshController {
    unowned let viewModel: AccountsMenuViewModel

    init(viewModel: AccountsMenuViewModel) {
        self.viewModel = viewModel
    }

    func performRefresh(refreshLive: Bool, allowAutoSwitch: Bool = true) async {
        let viewModel = viewModel
        if viewModel.pendingInteractiveLoginSession?.phase == .waitingForExternalCompletion {
            MultiCodexLog.log(.refresh, level: .debug, "Skipped refresh while interactive login is pending")
            return
        }

        if viewModel.isRefreshing {
            MultiCodexLog.log(.refresh, level: .debug, "Skipped refresh because another refresh is already running")
            return
        }

        MultiCodexLog.log(.refresh, level: .info, "Starting refresh", metadata: ["live": refreshLive ? "yes" : "no"])
        viewModel.isRefreshing = true
        let previousAccounts = viewModel.accounts

        // Proactively refresh aging tokens before fetching usage
        if refreshLive {
            let tokenErrors = viewModel.accountService.refreshStaleTokens()
            if !tokenErrors.isEmpty {
                MultiCodexLog.log(
                    .auth,
                    level: .info,
                    "Some token refreshes failed",
                    metadata: ["failedAccounts": tokenErrors.keys.sorted().joined(separator: ",")]
                )
            }
        }
        var fetchedAccounts: AccountsListPayload?
        var switchRecommendation: AccountSwitchRecommendation?
        defer {
            viewModel.isRefreshing = false
            if let switchRecommendation {
                applyAutomaticSwitch(recommendation: switchRecommendation)
            }
        }

        do {
            let accountsPayload = try await viewModel.accountService.fetchAccounts()
            fetchedAccounts = accountsPayload
            applyMergedAccounts(
                accountsPayload: accountsPayload,
                limits: LimitsPayload(results: [], errors: []),
                previousAccounts: previousAccounts
            )

            let limits = try await viewModel.accountService.fetchLimits(refreshLive: refreshLive)

            applyMergedAccounts(
                accountsPayload: accountsPayload,
                limits: limits,
                previousAccounts: previousAccounts
            )
            let quotaTransitions = QuotaTransitionDetector.detectTransitions(
                previous: previousAccounts,
                current: viewModel.accounts
            )
            if !quotaTransitions.isEmpty, viewModel.autoSwitchNotificationsEnabled {
                QuotaTransitionNotificationCenter.shared.post(transitions: quotaTransitions)
            }

            viewModel.lastUpdatedAt = Date()
            viewModel.cliResolutionHint = viewModel.accountService.resolutionHint
            if allowAutoSwitch, viewModel.switchingAccountName == nil {
                switchRecommendation = AccountSwitchRecommendationService.recommendation(
                    for: viewModel.accountSwitchingStrategy,
                    accounts: viewModel.accounts
                )
            }

            if limits.errors.isEmpty {
                viewModel.lastRefreshError = nil
                viewModel.refreshWarningMessage = nil
            } else {
                viewModel.lastRefreshError = nil
                viewModel.refreshWarningMessage = formatRefreshWarning(from: limits.errors)
            }
            MultiCodexLog.log(
                .refresh,
                level: limits.errors.isEmpty ? .info : .error,
                "Refresh completed",
                metadata: [
                    "accounts": "\(viewModel.accounts.count)",
                    "limitErrors": "\(limits.errors.count)",
                ]
            )

            performReconciliation(accountsPayload: accountsPayload)
        } catch {
            MultiCodexLog.log(.refresh, level: .error, "Refresh failed: \(error.localizedDescription)")
            viewModel.cliResolutionHint = viewModel.accountService.resolutionHint
            if let fetchedAccounts {
                applyMergedAccounts(
                    accountsPayload: fetchedAccounts,
                    limits: LimitsPayload(results: [], errors: []),
                    previousAccounts: previousAccounts
                )
                viewModel.lastRefreshError = nil
                viewModel.refreshWarningMessage = "Loaded accounts, but usage refresh failed: \(error.localizedDescription)"
            } else if previousAccounts.isEmpty {
                viewModel.lastRefreshError = error.localizedDescription
                viewModel.refreshWarningMessage = nil
            } else {
                viewModel.lastRefreshError = nil
                viewModel.refreshWarningMessage = "Refresh failed. Showing latest data."
            }
        }
    }

    func triggerRefresh(refreshLive: Bool) {
        let viewModel = viewModel
        Task {
            await viewModel.refreshController.performRefresh(refreshLive: refreshLive)
        }
    }

    func applyAutomaticSwitch(recommendation: AccountSwitchRecommendation) {
        let viewModel = viewModel
        viewModel.runSwitchAction(named: recommendation.accountName) {
            try await viewModel.accountService.switchAccount(name: recommendation.accountName)
            viewModel.lastRefreshError = nil
            viewModel.applyCurrentAccountLocally(named: recommendation.accountName)
            let message: String
            if let previousAccountName = recommendation.previousAccountName {
                message = "Auto-switched \(previousAccountName) -> \(recommendation.accountName). \(recommendation.reason)."
            } else {
                message = "Auto-switched to \(recommendation.accountName). \(recommendation.reason)."
            }
            viewModel.accountActions.setAccountFeedback(
                message: message,
                error: nil
            )
            if viewModel.autoSwitchNotificationsEnabled {
                viewModel.autoSwitchNotifier.send(
                    AutoSwitchNotificationPayload(
                        previousAccountName: recommendation.previousAccountName,
                        newAccountName: recommendation.accountName,
                        reason: recommendation.reason
                    )
                )
            }
            Task { @MainActor in
                await viewModel.refreshController.performRefresh(refreshLive: false, allowAutoSwitch: false)
            }
        }
    }

    func handleDidBecomeActive() {
        guard let session = viewModel.pendingInteractiveLoginSession, session.phase == .waitingForExternalCompletion else {
            triggerRefresh(refreshLive: true)
            return
        }

        viewModel.accountActions.resumePendingInteractiveLogin(session)
    }

    func refreshRuntimeProbe() {
        let probe = viewModel.accountService.probeRuntime()
        viewModel.isCodexRuntimeAvailable = probe.isAvailable
        viewModel.runtimeProbeSummary = probe.summary
    }

    func formatRefreshWarning(from errors: [LimitsErrorEntry]) -> String {
        let previews = errors.prefix(2).map { "\($0.account): \($0.message)" }
        let suffix: String
        if errors.count > previews.count {
            suffix = " (+\(errors.count - previews.count) more)"
        } else {
            suffix = ""
        }
        return "Some accounts could not refresh. " + previews.joined(separator: " | ") + suffix
    }

    private func applyMergedAccounts(
        accountsPayload: AccountsListPayload,
        limits: LimitsPayload,
        previousAccounts: [AccountUsage]
    ) {
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
                accounts: accountsPayload,
                limits: limits,
                previousAccounts: previousAccounts
            )
        )
        viewModel.clearFocusedAccountIfMissing()
        viewModel.syncSelectedSettingsAccount()
    }

    private func performReconciliation(accountsPayload: AccountsListPayload) {
        let service = viewModel.accountService
        let paths = service.currentPaths()
        let systemAuthPath = paths.defaultCodexAuthPath

        let systemModified = try? FileManager.default
            .attributesOfItem(atPath: systemAuthPath)[.modificationDate] as? Date

        let systemIdentity: ResolvedAccountIdentity?
        if let authData = try? Data(contentsOf: URL(fileURLWithPath: systemAuthPath)),
           let payload = try? JSONSerialization.jsonObject(with: authData) as? [String: Any]
        {
            systemIdentity = service.resolveFromAuthPayload(payload)
        } else {
            systemIdentity = nil
        }

        var accountIdentities: [String: AccountIdentity] = [:]
        for account in viewModel.accounts {
            let resolvedIdentity = service.resolvedIdentityForAccount(name: account.name)
            let accountId = resolvedIdentity?.accountId
            let email = resolvedIdentity?.email ?? account.defaultWorkspaceEmail
            accountIdentities[account.name] = AccountIdentityResolver.resolve(
                accountId: accountId,
                email: email
            )
        }

        let currentAccount = accountsPayload.currentAccount
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: currentAccount,
            systemAuthLastModified: systemModified,
            knownAccountLastModified: nil,
            systemIdentity: systemIdentity,
            accountIdentities: accountIdentities
        )

        if !result.isInSync {
            MultiCodexLog.log(
                .auth,
                level: .info,
                "Account out of sync with system auth",
                metadata: [
                    "configAccount": result.configCurrentAccount ?? "none",
                    "detectedAccount": result.detectedAccountName ?? "unknown",
                    "detectedEmail": result.detectedEmail ?? "none",
                    "externallyModified": result.systemAuthChangedExternally ? "yes" : "unknown",
                ]
            )

            if let detectedName = result.detectedAccountName {
                viewModel.applyCurrentAccountLocally(named: detectedName)
            } else if let email = result.detectedEmail {
                viewModel.refreshWarningMessage = "Detected external login for \(email). This account is not in MultiCodex."
            }
        }
    }
}
