import AppKit
import Foundation

@MainActor
final class AccountManagementController {
    unowned let viewModel: AccountsMenuViewModel

    init(viewModel: AccountsMenuViewModel) {
        self.viewModel = viewModel
    }

    func beginAccountRemoval(named name: String, deleteData: Bool) {
        viewModel.pendingAccountRemovalRequest = PendingAccountRemovalRequest(accountName: name, deleteData: deleteData)
    }

    func cancelPendingAccountRemoval() {
        viewModel.pendingAccountRemovalRequest = nil
    }

    func executePendingAccountRemoval(confirming typedName: String?) {
        guard let request = viewModel.pendingAccountRemovalRequest else {
            return
        }

        if request.deleteData {
            let normalizedTyped = (typedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedTyped != request.accountName {
                viewModel.accountActions.setAccountFeedback(message: nil, error: "Type the account name to confirm delete-data removal.")
                return
            }
        }

        viewModel.pendingAccountRemovalRequest = nil
        removeAccount(named: request.accountName, deleteData: request.deleteData)
    }

    func switchToAccount(named name: String) {
        viewModel.runSwitchAction(named: name) {
            try await self.viewModel.accountService.switchAccount(name: name)
            self.viewModel.lastRefreshError = nil
            self.viewModel.applyCurrentAccountLocally(named: name)
            self.viewModel.focusedAccountName = name
            self.viewModel.settingsController.syncSelectedSettingsAccount()
            self.viewModel.accountActions.setAccountFeedback(message: "Now using \(name).", error: nil)
            Task { @MainActor in
                await self.viewModel.refreshController.performRefresh(refreshLive: false, allowAutoSwitch: false)
            }
        }
    }

    func startNewAccountLogin() {
        accountActions.startLoginFlow(accountName: generateRandomAccountName(), createIfNeeded: true)
    }

    func renameAccount(from oldName: String, to rawNewName: String) {
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
            _ = try await self.viewModel.accountService.renameAccount(from: oldName, to: newName)
            if self.viewModel.selectedSettingsAccountName == oldName {
                self.viewModel.settingsController.selectSettingsAccount(named: newName)
            }
            return AccountActionOutcome.success("Renamed \(oldName) to \(newName).")
        }
    }

    func removeAccount(named name: String, deleteData: Bool) {
        if viewModel.pendingAccountRemovalRequest?.accountName == name {
            viewModel.pendingAccountRemovalRequest = nil
        }
        accountActions.runAccountAction(for: name) {
            _ = try await self.viewModel.accountService.removeAccount(name: name, deleteData: deleteData)
            if self.viewModel.selectedSettingsAccountName == name {
                self.viewModel.settingsController.selectSettingsAccount(named: nil)
            }
            return AccountActionOutcome.success(deleteData ? "Removed \(name) and deleted stored data." : "Removed \(name).")
        }
    }

    func importCurrentAuth(into name: String) {
        accountActions.runAccountAction(for: name) {
            _ = try await self.viewModel.accountService.importDefaultAuth(into: name)
            return AccountActionOutcome.success("Imported current ~/.codex/auth.json into \(name).")
        }
    }

    func checkLoginStatus(for name: String) {
        accountActions.runAccountAction(for: name) {
            let status = try await self.viewModel.accountService.fetchStatus(name: name)
            let summary = status.output.trimmingCharacters(in: .whitespacesAndNewlines)
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
