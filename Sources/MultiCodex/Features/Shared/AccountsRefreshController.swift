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
            return
        }

        if viewModel.isRefreshing {
            return
        }

        viewModel.isRefreshing = true
        let previousAccounts = viewModel.accounts
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
        } catch {
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
        viewModel.accounts = AccountUsageMergeService.mergeAccounts(
            accounts: accountsPayload,
            limits: limits,
            previousAccounts: previousAccounts
        )
        viewModel.clearFocusedAccountIfMissing()
        viewModel.syncSelectedSettingsAccount()
    }
}
