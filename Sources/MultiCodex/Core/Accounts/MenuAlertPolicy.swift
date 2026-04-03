import Foundation

enum MenuAlertPolicy {
    static func prioritizedAlert(
        isRuntimeAvailable: Bool,
        runtimeSummary: String?,
        lastRefreshError: String?,
        accountsNeedingLogin: [AccountUsage]
    ) -> MenuAlertState? {
        if !isRuntimeAvailable {
            return MenuAlertState(
                severity: .runtimeUnavailable,
                title: "Codex runtime unavailable",
                message: runtimeSummary ?? "Set the runtime path in Settings.",
                actionTitle: "Open Runtime Settings",
                action: .openRuntimeSettings
            )
        }

        if let lastRefreshError {
            return MenuAlertState(
                severity: .refreshError,
                title: "Refresh failed",
                message: lastRefreshError,
                actionTitle: "Refresh Live",
                action: .refreshLive
            )
        }

        if let accountNeedingLogin = accountsNeedingLogin.first {
            return MenuAlertState(
                severity: .authRequired,
                title: "Account needs login",
                message: "\(accountNeedingLogin.name) requires authentication.",
                actionTitle: "Re-login \(accountNeedingLogin.name)",
                action: .relogin(accountName: accountNeedingLogin.name)
            )
        }

        return nil
    }
}
