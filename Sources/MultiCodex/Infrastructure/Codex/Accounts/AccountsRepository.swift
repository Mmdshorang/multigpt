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
                || managedAuthPath(for: name, paths: paths) != nil
            return AccountEntry(
                name: name,
                isCurrent: name == config.currentAccount,
                hasAuth: hasAuth,
                lastUsedAt: meta?.lastUsedAt,
                lastLoginStatus: meta?.lastLoginStatus,
                defaultWorkspaceEmail: inferDefaultWorkspaceEmail(fromAuthPath: managedAuthPath(for: name, paths: paths) ?? paths.accountAuthPath(name))
            )
        }

        return AccountsListPayload(accounts: accounts, currentAccount: config.currentAccount)
    }

    func addAccountIfNeededNow(name: String) throws -> AddAccountPayload {
        try addAccountCore(name: name, onExisting: .ignore, selectIfFirst: true)
    }

    func addAccountIfNeededForLoginNow(name: String) throws -> AddAccountPayload {
        try addAccountCore(name: name, onExisting: .ignore, selectIfFirst: false)
    }

    func addAccountNow(name: String) throws -> AddAccountPayload {
        try addAccountCore(name: name, onExisting: .fail, selectIfFirst: true)
    }

    func addAccountCore(name: String, onExisting: ExistingAccountBehavior, selectIfFirst: Bool) throws -> AddAccountPayload {
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
        if config.currentAccount == nil, selectIfFirst {
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

        let lock = try acquireAuthLock(account: account, force: false, paths: paths)
        defer { lock.release() }
        try AuthSwapService.switchToAccount(
            named: account,
            previousAccountName: config.currentAccount,
            paths: paths
        )
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

        let removedCurrentAccount = config.currentAccount == account
        config.accounts.remove(account)
        if removedCurrentAccount {
            config.currentAccount = config.accounts.sorted().first
        }

        if removedCurrentAccount {
            if let nextAccount = config.currentAccount {
                try applyAccountAuthToDefault(account: nextAccount, forceLock: false, paths: paths)
            } else {
                try AuthSwapService.clearSystemAuth(paths: paths)
            }
        }

        try saveConfig(config, paths: paths)

        if deleteData {
            try? fileManager.removeItem(atPath: paths.accountDir(account))
            removeManagedHomeIfNeeded(account: account, paths: paths)
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
        renameManagedHomeIfNeeded(from: source, to: target, paths: paths)

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

    func persistCurrentAccountIfKnown(_ name: String) throws {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        var config = try loadConfig(paths: paths)
        guard config.accounts.contains(account) else {
            throw CodexAccountServiceError(message: "Unknown account: \(account)")
        }
        config.currentAccount = account
        try saveConfig(config, paths: paths)
    }

    private func renameManagedHomeIfNeeded(from source: String, to target: String, paths: PathContext) {
        guard isManagedHomeMigrationComplete(paths: paths),
              let sourceHome = ManagedCodexHomeFactory.homeURL(for: source, multicodexHome: paths.multicodexHome)
        else {
            return
        }

        let targetHome = ManagedCodexHomeFactory.scopedRootURL(multicodexHome: paths.multicodexHome)
            .appendingPathComponent(ManagedCodexHomeFactory.sanitize(target), isDirectory: true)
        try? fileManager.removeItem(at: targetHome)
        try? fileManager.moveItem(at: sourceHome, to: targetHome)
    }

    private func removeManagedHomeIfNeeded(account: String, paths: PathContext) {
        guard isManagedHomeMigrationComplete(paths: paths),
              let home = ManagedCodexHomeFactory.homeURL(for: account, multicodexHome: paths.multicodexHome)
        else {
            return
        }

        let rootPath = ManagedCodexHomeFactory.scopedRootURL(multicodexHome: paths.multicodexHome)
            .standardizedFileURL.path
        let targetPath = home.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(rootPrefix), targetPath != rootPath else {
            return
        }
        try? fileManager.removeItem(at: home)
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

    func importAuthNow(fromHome homePath: String, into name: String) throws -> ImportAccountPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        let config = try loadConfig(paths: paths)
        guard config.accounts.contains(account) else {
            throw CodexAccountServiceError(message: "Unknown account: \(account)")
        }

        let sourceAuthPath = (homePath as NSString).appendingPathComponent(".codex/auth.json")
        guard let authData = fileManager.contents(atPath: sourceAuthPath), !authData.isEmpty else {
            throw CodexAccountServiceError(message: "Login did not produce a usable auth session.")
        }

        let lock = try acquireAuthLock(account: account, force: false, paths: paths)
        defer { lock.release() }

        try createDirectory(path: paths.accountDir(account), mode: 0o700)
        try writeFileAtomic(data: authData, path: paths.accountAuthPath(account), mode: 0o600)
        if let managedHome = managedHomeForMutatingAuth(account: account, paths: paths) {
            try ManagedCodexHomeFactory.writeAuthData(authData, to: managedHome)
        }
        _ = try updateAccountMeta(account: account, paths: paths) { meta in
            meta.lastUsedAt = Self.nowISO()
        }

        return ImportAccountPayload(account: account)
    }

}
