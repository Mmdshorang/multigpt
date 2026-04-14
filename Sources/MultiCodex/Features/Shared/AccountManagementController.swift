import AppKit
import Foundation

@MainActor
final class AccountManagementController {
    unowned let viewModel: AccountsMenuViewModel

    init(viewModel: AccountsMenuViewModel) {
        self.viewModel = viewModel
    }

    func switchToAccount(named name: String) {
        let viewModel = viewModel
        viewModel.runSwitchAction(named: name) {
            try await viewModel.accountService.switchAccount(name: name)
            viewModel.lastRefreshError = nil
            viewModel.applyCurrentAccountLocally(named: name)
            viewModel.focusedAccountName = name
            viewModel.settingsController.syncSelectedSettingsAccount()
            viewModel.accountActions.setAccountFeedback(message: "Now using \(name).", error: nil)
            Task { @MainActor in
                await viewModel.refreshController.performRefresh(refreshLive: false, allowAutoSwitch: false)
            }
        }
    }

    func startNewAccountLogin() {
        accountActions.startLoginFlow(accountName: generateRandomAccountName(), createIfNeeded: true)
    }

    func renameAccount(from oldName: String, to rawNewName: String) {
        let viewModel = viewModel
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            viewModel.accountActionError = "New account name cannot be empty."
            viewModel.accountActionMessage = nil
            return
        }

        guard oldName != newName else {
            viewModel.accountActionError = nil
            viewModel.accountActionMessage = "Account name is unchanged."
            return
        }

        accountActions.runAccountAction(for: oldName) {
            _ = try await viewModel.accountService.renameAccount(from: oldName, to: newName)
            viewModel.renameAccountLocally(from: oldName, to: newName)
            if viewModel.selectedSettingsAccountName == oldName {
                viewModel.settingsController.selectSettingsAccount(named: newName)
            }
            return AccountActionOutcome.success("Renamed \(oldName) to \(newName).")
        }
    }

    func removeAccount(named name: String, deleteData: Bool) {
        let viewModel = viewModel
        accountActions.runAccountAction(for: name) {
            let payload = try await viewModel.accountService.removeAccount(name: name, deleteData: deleteData)
            viewModel.removeAccountLocally(named: name, currentAccountName: payload.currentAccount)
            if viewModel.selectedSettingsAccountName == name {
                viewModel.settingsController.selectSettingsAccount(named: nil)
            }
            return AccountActionOutcome.success(deleteData ? "Removed \(name) and deleted stored data." : "Removed \(name).")
        }
    }

    func importCurrentAuth(into name: String) {
        let viewModel = viewModel
        accountActions.runAccountAction(for: name) {
            _ = try await viewModel.accountService.importDefaultAuth(into: name)
            viewModel.upsertAuthenticatedAccountLocally(named: name)
            return AccountActionOutcome.success("Imported current ~/.codex/auth.json into \(name).")
        }
    }

    func checkLoginStatus(for name: String) {
        let viewModel = viewModel
        accountActions.runAccountAction(for: name) {
            let status = try await viewModel.accountService.fetchStatus(name: name)
            let summary = status.output.trimmingCharacters(in: .whitespacesAndNewlines)
            viewModel.upsertAuthenticatedAccountLocally(
                named: name,
                lastLoginStatus: summary.isEmpty ? nil : summary
            )
            if status.exitCode == 0 {
                return AccountActionOutcome.success(summary.isEmpty ? "\(name): login status is OK." : "\(name): \(summary)")
            }
            return AccountActionOutcome.failure(summary.isEmpty ? "\(name): login check failed." : "\(name): \(summary)")
        }
    }

    func openLoginInTerminal(for name: String) {
        accountActions.startLoginFlow(accountName: name, createIfNeeded: false)
    }

    func clearAccountActionFeedback() {
        viewModel.feedbackAutoClearTask?.cancel()
        viewModel.feedbackAutoClearTask = nil
        accountActions.setAccountFeedback(message: nil, error: nil)
    }

    func sendTestAutoSwitchNotification() {
        guard viewModel.autoSwitchNotificationsEnabled else {
            viewModel.accountActions.setAccountFeedback(message: nil, error: "Enable auto-switch notifications to send a test.")
            return
        }

        let previousAccountName = viewModel.currentAccount?.name ?? viewModel.accounts.first?.name ?? "alpha"
        let newAccountName = viewModel.accounts.first(where: { $0.name != previousAccountName })?.name ?? "beta"
        let payload = AutoSwitchNotificationPayload(
            previousAccountName: previousAccountName,
            newAccountName: newAccountName,
            reason: "5h window expiring"
        )

        viewModel.autoSwitchNotifier.send(payload)
        viewModel.accountActions.setAccountFeedback(
            message: "Sent test notification \(previousAccountName) -> \(newAccountName).",
            error: nil
        )
    }

    func openMulticodexConfigDirectory() {
        let url = URL(fileURLWithPath: viewModel.accountService.effectiveMulticodexHomePath(), isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    private var accountActions: AccountActionController { viewModel.accountActions }

    private func generateRandomAccountName() -> String {
        let existing = Set(viewModel.accounts.map(\.name))
        for _ in 0..<20 {
            let random = UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
            let candidate = "account-\(random.prefix(6))"
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "account-\(Int(Date().timeIntervalSince1970))"
    }
}
