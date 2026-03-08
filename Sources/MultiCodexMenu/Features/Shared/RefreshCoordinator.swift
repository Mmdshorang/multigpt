import Foundation

private enum RefreshCoordinator {}

extension AccountsMenuViewModel {
    func performRefresh(refreshLive: Bool) async {
        if pendingInteractiveLoginAccount != nil {
            return
        }

        if isRefreshing {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let previousAccounts = accounts

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
