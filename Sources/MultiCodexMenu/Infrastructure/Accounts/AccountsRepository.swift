import Foundation

// AccountsRepository
extension CodexAccountService {

    func fetchAccountsNow() throws -> AccountsListPayload {
        let paths = currentPaths()
        let config = try loadConfig(paths: paths)
        let names = config.accounts.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        let accounts: [AccountEntry] = names.map { name in
            let meta = readAccountMeta(account: name, paths: paths)
            let hasAuth = fileManager.fileExists(atPath: paths.accountAuthPath(name))
            return AccountEntry(
                name: name,
                isCurrent: name == config.currentAccount,
                hasAuth: hasAuth,
                lastUsedAt: meta?.lastUsedAt,
                lastLoginStatus: meta?.lastLoginStatus
            )
        }

        return AccountsListPayload(accounts: accounts, currentAccount: config.currentAccount)
    }

    func addAccountIfNeededNow(name: String) throws -> AddAccountPayload {
        try addAccountCore(name: name, onExisting: .ignore)
    }

    func addAccountNow(name: String) throws -> AddAccountPayload {
        try addAccountCore(name: name, onExisting: .fail)
    }

    func addAccountCore(name: String, onExisting: ExistingAccountBehavior) throws -> AddAccountPayload {
        let account = try validatedAccountName(name)
        let paths = currentPaths()
        var config = try loadConfig(paths: paths)

        if config.accounts.contains(account) {
            if onExisting == .fail {
                throw CodexAccountServiceError(message: "Account already exists: \(account)")
            }
            return AddAccountPayload(account: account, currentAccount: config.currentAccount)
        }

        try createDirectory(path: paths.accountDir(account), mode: 0o700)
        _ = try ensureAccountMeta(account: account, paths: paths)

        config.accounts.insert(account)
        if config.currentAccount == nil {
            config.currentAccount = account
        }
        try saveConfig(config, paths: paths)

        return AddAccountPayload(account: account, currentAccount: config.currentAccount)
    }

    func switchAccountNow(name: String) throws -> SwitchAccountPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        var config = try loadConfig(paths: paths)

        guard config.accounts.contains(account) else {
            throw CodexAccountServiceError(message: "Unknown account: \(account)")
        }

        try applyAccountAuthToDefault(account: account, forceLock: false, paths: paths)

        config.currentAccount = account
        try saveConfig(config, paths: paths)
        _ = try updateAccountMeta(account: account, paths: paths) { meta in
            meta.lastUsedAt = Self.nowISO()
        }

        return SwitchAccountPayload(currentAccount: account)
    }

    func removeAccountNow(name: String, deleteData: Bool) throws -> RemoveAccountPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        var config = try loadConfig(paths: paths)

        guard config.accounts.contains(account) else {
            throw CodexAccountServiceError(message: "Unknown account: \(account)")
        }

        config.accounts.remove(account)
        if config.currentAccount == account {
            config.currentAccount = config.accounts.sorted().first
        }

        try saveConfig(config, paths: paths)

        if deleteData {
            try? fileManager.removeItem(atPath: paths.accountDir(account))
        }

        return RemoveAccountPayload(removedAccount: account, currentAccount: config.currentAccount)
    }

    func renameAccountNow(from oldName: String, to newName: String) throws -> RenameAccountPayload {
        let source = normalizeAccountName(oldName)
        let target = try validatedAccountName(newName)

        let paths = currentPaths()
        var config = try loadConfig(paths: paths)

        guard config.accounts.contains(source) else {
            throw CodexAccountServiceError(message: "Unknown account: \(source)")
        }
        guard !config.accounts.contains(target) else {
            throw CodexAccountServiceError(message: "Account already exists: \(target)")
        }

        let srcDir = paths.accountDir(source)
        let dstDir = paths.accountDir(target)
        if fileManager.fileExists(atPath: srcDir) {
            try fileManager.moveItem(atPath: srcDir, toPath: dstDir)
        } else {
            try createDirectory(path: dstDir, mode: 0o700)
        }

        config.accounts.remove(source)
        config.accounts.insert(target)
        if config.currentAccount == source {
            config.currentAccount = target
        }

        try saveConfig(config, paths: paths)
        _ = try updateAccountMeta(account: target, paths: paths) { meta in
            meta.lastUsedAt = Self.nowISO()
        }

        return RenameAccountPayload(from: source, to: target, currentAccount: config.currentAccount)
    }

    func importDefaultAuthNow(into name: String) throws -> ImportAccountPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        let config = try loadConfig(paths: paths)
        guard config.accounts.contains(account) else {
            throw CodexAccountServiceError(message: "Unknown account: \(account)")
        }

        let lock = try acquireAuthLock(account: account, force: false, paths: paths)
        defer { lock.release() }

        try snapshotDefaultAuthToAccount(account: account, paths: paths)
        _ = try updateAccountMeta(account: account, paths: paths) { meta in
            meta.lastUsedAt = Self.nowISO()
        }

        return ImportAccountPayload(account: account)
    }

}
