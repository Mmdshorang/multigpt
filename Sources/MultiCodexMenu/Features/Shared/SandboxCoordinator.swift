import AppKit
import Foundation

private enum SandboxCoordinator {}

extension AccountsMenuViewModel {
    func configureSandboxEnvironment() {
        guard isUsingTemporaryAuthSandbox else {
            accountService.sandboxHomeDirectory = nil
            accountService.sandboxMulticodexHomeDirectory = nil
            return
        }

        if let sandboxHome = temporaryAuthSandboxHome?.trimmingCharacters(in: .whitespacesAndNewlines), !sandboxHome.isEmpty {
            do {
                try ensureSandboxDirectories(homePath: sandboxHome)
                accountService.sandboxHomeDirectory = sandboxHome
                accountService.sandboxMulticodexHomeDirectory = (sandboxHome as NSString).appendingPathComponent(".config/multicodex")
                return
            } catch {
                setAccountFeedback(message: nil, error: "Could not prepare temporary auth sandbox: \(error.localizedDescription)")
            }
        }

        isUsingTemporaryAuthSandbox = false
        preferences.temporaryAuthSandboxEnabled = false
        accountService.sandboxHomeDirectory = nil
        accountService.sandboxMulticodexHomeDirectory = nil
    }

    func prepareFreshTemporaryAuthSandbox() throws -> String {
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("multicodex-test-\(UUID().uuidString)", isDirectory: true)
        try ensureSandboxDirectories(homePath: rootURL.path)
        return rootURL.path
    }

    func ensureSandboxDirectories(homePath: String) throws {
        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let codexURL = homeURL.appendingPathComponent(".codex", isDirectory: true)
        let multicodexURL = homeURL.appendingPathComponent(".config/multicodex", isDirectory: true)
        try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: codexURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: multicodexURL, withIntermediateDirectories: true)
    }

    func syncSelectedSettingsAccount() {
        let candidates = filteredAccounts
        guard !candidates.isEmpty else {
            selectedSettingsAccountName = nil
            preferences.selectedSettingsAccountName = nil
            return
        }

        if let selectedSettingsAccountName,
           candidates.contains(where: { $0.name == selectedSettingsAccountName })
        {
            return
        }

        if let currentAccount,
           candidates.contains(where: { $0.name == currentAccount.name })
        {
            selectSettingsAccount(named: currentAccount.name)
            return
        }

        selectSettingsAccount(named: candidates.first?.name)
    }

    func generateRandomAccountName() -> String {
        let existing = Set(accounts.map(\.name))
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

    func openTemporaryAuthSandboxDirectory() {
        guard let sandbox = temporaryAuthSandboxHome, !sandbox.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: sandbox, isDirectory: true))
    }

    func updateCustomCodexPath(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        customCodexPath = trimmed
        preferences.customCodexPath = trimmed
        accountService.customCodexPath = trimmed.isEmpty ? nil : trimmed
        refreshRuntimeProbe()
        refresh()
    }

    func clearCustomCodexPath() {
        updateCustomCodexPath("")
    }

    func dismissFocusHint() {
        focusedAccountName = nil
    }

    func chooseCustomCodexPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Use"
        panel.message = "Choose the codex executable"

        if panel.runModal() == .OK, let path = panel.url?.path {
            updateCustomCodexPath(path)
        }
    }
}
