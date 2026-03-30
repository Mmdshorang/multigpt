import Foundation

private enum RefreshCoordinator {}

extension AccountsMenuViewModel {
    func performRefresh(refreshLive: Bool, allowAutoSwitch: Bool = true) async {
        if pendingInteractiveLoginSession?.phase == .waitingForExternalCompletion {
            return
        }

        if isRefreshing {
            return
        }

        isRefreshing = true
        let previousAccounts = accounts
        var fetchedAccounts: AccountsListPayload?
        var switchRecommendation: AccountSwitchRecommendation?
        defer {
            isRefreshing = false
            if let switchRecommendation {
                applyAutomaticSwitch(recommendation: switchRecommendation)
            }
        }

        do {
            let accountsPayload = try await accountService.fetchAccounts()
            fetchedAccounts = accountsPayload
            accounts = AccountUsageMergeService.mergeAccounts(
                accounts: accountsPayload,
                limits: LimitsPayload(results: [], errors: []),
                previousAccounts: previousAccounts
            )
            if let focused = focusedAccountName, !accounts.contains(where: { $0.name == focused }) {
                focusedAccountName = nil
            }
            syncSelectedSettingsAccount()

            let limits = try await accountService.fetchLimits(refreshLive: refreshLive)

            accounts = AccountUsageMergeService.mergeAccounts(
                accounts: accountsPayload,
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
                lastRefreshError = nil
                refreshWarningMessage = formatRefreshWarning(from: limits.errors)
            }
        } catch {
            cliResolutionHint = accountService.resolutionHint
            if let fetchedAccounts {
                accounts = AccountUsageMergeService.mergeAccounts(
                    accounts: fetchedAccounts,
                    limits: LimitsPayload(results: [], errors: []),
                    previousAccounts: previousAccounts
                )
                if let focused = focusedAccountName, !accounts.contains(where: { $0.name == focused }) {
                    focusedAccountName = nil
                }
                syncSelectedSettingsAccount()
                lastRefreshError = nil
                refreshWarningMessage = "Loaded accounts, but usage refresh failed: \(error.localizedDescription)"
            } else if previousAccounts.isEmpty {
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
        guard let session = pendingInteractiveLoginSession, session.phase == .waitingForExternalCompletion else {
            refreshLive()
            return
        }

        resumePendingInteractiveLogin(session)
    }

    func refreshRuntimeProbe() {
        let probe = accountService.probeRuntime()
        isCodexRuntimeAvailable = probe.isAvailable
        runtimeProbeSummary = probe.summary
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
}
