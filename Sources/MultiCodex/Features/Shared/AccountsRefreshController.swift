import Foundation

@MainActor
final class AccountsRefreshController {
    unowned let viewModel: AccountsMenuViewModel
    private let usagePaceStore = UsagePaceStore()

    init(viewModel: AccountsMenuViewModel) {
        self.viewModel = viewModel
    }

    func performRefresh(refreshLive: Bool, allowAutoSwitch: Bool = true, generation: Int? = nil) async {
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
            let tokenErrors = await viewModel.accountService.refreshStaleTokens()
            if isRefreshStale(generation: generation) {
                viewModel.isRefreshing = false
                return
            }
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
            if isRefreshStale(generation: generation) {
                viewModel.isRefreshing = false
                return
            }
            fetchedAccounts = accountsPayload
            await applyMergedAccounts(
                accountsPayload: accountsPayload,
                limits: LimitsPayload(results: [], errors: []),
                previousAccounts: previousAccounts,
                recordPace: false
            )

            let cancellationToken = RefreshCancellationToken()
            let limits = try await withTaskCancellationHandler {
                try await viewModel.accountService.fetchLimits(
                    refreshLive: refreshLive,
                    cancellationToken: cancellationToken
                ) { [weak self] partial in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.isRefreshStale(generation: generation) {
                            return
                        }
                        await self.applyMergedAccounts(
                            accountsPayload: accountsPayload,
                            limits: partial,
                            previousAccounts: previousAccounts,
                            recordPace: false
                        )
                    }
                }
            } onCancel: {
                cancellationToken.cancel()
            }
            if isRefreshStale(generation: generation) {
                viewModel.isRefreshing = false
                return
            }

            await applyMergedAccounts(
                accountsPayload: accountsPayload,
                limits: limits,
                previousAccounts: previousAccounts,
                recordPace: true
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
            if allowAutoSwitch, viewModel.accountSwitchingStrategy != .manual, viewModel.switchingAccountName == nil {
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
            if isRefreshStale(generation: generation) || error is CancellationError {
                return
            }
            MultiCodexLog.log(.refresh, level: .error, "Refresh failed: \(error.localizedDescription)")
            viewModel.cliResolutionHint = viewModel.accountService.resolutionHint
            if let fetchedAccounts {
                await applyMergedAccounts(
                    accountsPayload: fetchedAccounts,
                    limits: LimitsPayload(results: [], errors: []),
                    previousAccounts: previousAccounts,
                    recordPace: false
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

    func performStartupRefresh() async {
        let viewModel = viewModel
        guard !viewModel.isRefreshing else {
            return
        }

        viewModel.isRefreshing = true
        let previousAccounts = viewModel.accounts

        do {
            let accountsPayload = try await viewModel.accountService.fetchAccounts()
            let cachedLimits = try? await viewModel.accountService.fetchCachedLimits()
            await applyMergedAccounts(
                accountsPayload: accountsPayload,
                limits: cachedLimits ?? LimitsPayload(results: [], errors: []),
                previousAccounts: previousAccounts,
                recordPace: cachedLimits?.results.isEmpty == false
            )
            viewModel.lastRefreshError = nil
            viewModel.refreshWarningMessage = nil

            viewModel.isRefreshing = false
            triggerRefresh(refreshLive: viewModel.shouldPreferLiveRefreshForAutoSwitching)
        } catch {
            viewModel.lastRefreshError = error.localizedDescription
            viewModel.refreshWarningMessage = nil
            viewModel.isRefreshing = false
        }
    }

    // Invariant: all app refreshes go through this method so generation checks can drop stale results.
    func triggerRefresh(refreshLive: Bool, allowAutoSwitch: Bool = true) {
        let viewModel = viewModel
        viewModel.activeRefreshTask?.cancel()
        viewModel.refreshGeneration += 1
        let generation = viewModel.refreshGeneration
        viewModel.activeRefreshTask = Task { @MainActor in
            await viewModel.refreshController.performRefresh(
                refreshLive: refreshLive,
                allowAutoSwitch: allowAutoSwitch,
                generation: generation
            )
        }
    }

    func applyAutomaticSwitch(recommendation: AccountSwitchRecommendation) {
        let viewModel = viewModel
        guard viewModel.accountSwitchingStrategy != .manual else {
            MultiCodexLog.log(.refresh, level: .error, "applyAutomaticSwitch called while strategy is .manual — skipping switch to \(recommendation.accountName)")
            return
        }
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
            viewModel.refreshController.triggerRefresh(refreshLive: false, allowAutoSwitch: false)
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
        let previews = errors.prefix(2).map { "\($0.account): \(summarizeLimitsErrorMessage($0.message))" }
        let suffix: String
        if errors.count > previews.count {
            suffix = " (+\(errors.count - previews.count) more)"
        } else {
            suffix = ""
        }
        return "Some accounts could not refresh usage. " + previews.joined(separator: " | ") + suffix
    }

    private func summarizeLimitsErrorMessage(_ message: String) -> String {
        let lowered = message.lowercased()

        if lowered.contains("timed out") || lowered.contains("timeout") || lowered.contains("refresh timed out") {
            return "Timed out"
        }
        if lowered.contains("tls error") || lowered.contains("secure connection") {
            return "Secure connection failed"
        }
        if lowered.contains("http 401") || lowered.contains("unauthorized") || lowered.contains("needs login") {
            return "Sign-in required"
        }
        if lowered.contains("http 429") || lowered.contains("rate limit") {
            return "Rate-limited"
        }
        if lowered.contains("http 5") || lowered.contains("internal server error") || lowered.contains("service unavailable") {
            return "Service unavailable"
        }
        if lowered.contains("could not run") || lowered.contains("no such file") || lowered.contains("not found") {
            return "Runtime unavailable"
        }
        if lowered.contains("rpc fallback failed") || lowered.contains("rpc error") {
            return "Usage API failed"
        }
        if lowered.contains("api failed") || lowered.contains("usage request failed") {
            return "Usage request failed"
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Unknown error"
        }
        return String(trimmed.prefix(80))
    }

    private func applyMergedAccounts(
        accountsPayload: AccountsListPayload,
        limits: LimitsPayload,
        previousAccounts: [AccountUsage],
        recordPace: Bool
    ) async {
        viewModel.updateAccounts(
            AccountUsageMergeService.mergeAccounts(
                accounts: accountsPayload,
                limits: limits,
                previousAccounts: previousAccounts
            )
        )
        if recordPace {
            await usagePaceStore.record(accounts: viewModel.accounts)
        }
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
        let knownAccountModified = currentAccount.flatMap { service.storedAuthModifiedDate(for: $0, paths: paths) }
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: currentAccount,
            systemAuthLastModified: systemModified,
            knownAccountLastModified: knownAccountModified,
            systemIdentity: systemIdentity,
            accountIdentities: accountIdentities
        )

        if result.isInSync {
            viewModel.externalAuthImportCandidate = nil
            if viewModel.refreshWarningMessage?.hasPrefix("Detected external login") == true {
                viewModel.refreshWarningMessage = nil
            }
            return
        }

        if !result.isInSync {
            MultiCodexLog.log(
                .auth,
                level: .info,
                "Account out of sync with system auth",
                metadata: [
                    "configAccount": result.configCurrentAccount ?? "none",
                    "detectedAccount": result.detectedAccountName ?? "unknown",
                    "detectedEmail": result.detectedEmail ?? "none",
                    "externallyModified": result.systemAuthChangedExternally ? "yes" : "no",
                ]
            )

            if result.detectedAccountName == nil, let email = result.detectedEmail {
                viewModel.externalAuthImportCandidate = ExternalAuthImportCandidate(
                    accountName: email,
                    email: email
                )
                viewModel.refreshWarningMessage = nil
                return
            }

            viewModel.externalAuthImportCandidate = nil
            if viewModel.accountSwitchingStrategy == .manual {
                if result.systemAuthChangedExternally, let detectedName = result.detectedAccountName {
                    viewModel.refreshWarningMessage = "Detected external login for \(detectedName). Auto-switching is off."
                } else if result.systemAuthChangedExternally, let email = result.detectedEmail {
                    viewModel.refreshWarningMessage = "Detected external login for \(email). Auto-switching is off."
                }
            } else if let detectedName = result.detectedAccountName {
                do {
                    try service.persistCurrentAccountIfKnown(detectedName)
                    viewModel.applyCurrentAccountLocally(named: detectedName)
                } catch {
                    viewModel.refreshWarningMessage = "Detected account \(detectedName), but failed to persist reconciliation."
                }
            } else if result.systemAuthChangedExternally, let email = result.detectedEmail {
                viewModel.refreshWarningMessage = "Detected external login for \(email). This account is not in MultiCodex."
            }
        }
    }

    private func isRefreshStale(generation: Int?) -> Bool {
        Task.isCancelled || generation.map { $0 != viewModel.refreshGeneration } == true
    }
}
