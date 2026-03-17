import Foundation

private enum RefreshCoordinator {}

extension AccountsMenuViewModel {
    func performRefresh(refreshLive: Bool, allowAutoSwitch: Bool = true) async {
        if pendingInteractiveLoginAccount != nil {
            return
        }

        if isRefreshing {
            return
        }

        isRefreshing = true
        let previousAccounts = accounts
        var switchRecommendation: AccountSwitchRecommendation?
        defer {
            isRefreshing = false
            if let switchRecommendation {
                applyAutomaticSwitch(recommendation: switchRecommendation)
            }
        }

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
            if allowAutoSwitch, switchingAccountName == nil {
                switchRecommendation = AccountSwitchRecommendationService.recommendation(
                    for: accountSwitchingStrategy,
                    accounts: accounts
                )
            }

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

    func triggerRefresh(refreshLive: Bool) {
        Task {
            await performRefresh(refreshLive: refreshLive)
        }
    }

    func applyAutomaticSwitch(recommendation: AccountSwitchRecommendation) {
        runSwitchAction(named: recommendation.accountName) {
            try await self.accountService.switchAccount(name: recommendation.accountName)
            self.lastRefreshError = nil
            let message: String
            if let previousAccountName = recommendation.previousAccountName {
                message = "Auto-switched \(previousAccountName) -> \(recommendation.accountName). \(recommendation.reason)."
            } else {
                message = "Auto-switched to \(recommendation.accountName). \(recommendation.reason)."
            }
            self.setAccountFeedback(
                message: message,
                error: nil
            )
            if self.autoSwitchNotificationsEnabled {
                self.autoSwitchNotifier.send(
                    AutoSwitchNotificationPayload(
                        previousAccountName: recommendation.previousAccountName,
                        newAccountName: recommendation.accountName,
                        reason: recommendation.reason
                    )
                )
            }
            await self.performRefresh(refreshLive: true, allowAutoSwitch: false)
        }
    }

    func handleDidBecomeActive() {
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

    func refreshRuntimeProbe() {
        let probe = accountService.probeRuntime()
        isCodexRuntimeAvailable = probe.isAvailable
        runtimeProbeSummary = probe.summary
    }
}
