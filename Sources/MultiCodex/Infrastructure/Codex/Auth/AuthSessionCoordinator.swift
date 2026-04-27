import Darwin
import Foundation

// AuthSessionCoordinator + storage
extension CodexAccountService {

    func currentPaths(loginHome: String? = nil) -> PathContext {
        let processEnvironment = ProcessInfo.processInfo.environment
        let home = firstNonEmptyPath(
            fallback: NSHomeDirectory(),
            loginHome,
            sandboxHomeDirectory,
            processEnvironment["HOME"]
        )
        let multicodexHome = firstNonEmptyPath(
            fallback: (home as NSString).appendingPathComponent(".config/multicodex"),
            sandboxMulticodexHomeDirectory,
            processEnvironment["MULTICODEX_HOME"]
        )

        return PathContext(homeDir: home, multicodexHome: multicodexHome)
    }

    func loadConfig(paths: PathContext) throws -> NativeConfig {
        try AccountConfigStore.decodeConfig(from: readFileIfExists(paths.configPath))
    }

    func saveConfig(_ config: NativeConfig, paths: PathContext) throws {
        let data = try AccountConfigStore.encodeConfig(config)
        try writeFileAtomic(data: data + Data("\n".utf8), path: paths.configPath, mode: 0o600)
    }

    func createDirectory(path: String, mode: Int16) throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path)
    }

    func readFileIfExists(_ path: String) -> Data? {
        return fileManager.contents(atPath: path)
    }

    func writeFileAtomic(data: Data, path: String, mode: Int16) throws {
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            try createDirectory(path: dir, mode: 0o700)
        }

        let tmp = "\(path).tmp.\(UUID().uuidString)"
        guard fileManager.createFile(atPath: tmp, contents: data) else {
            throw CodexAccountServiceError(message: "Could not create temporary file at \(tmp).")
        }
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: tmp)

        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
        try fileManager.moveItem(atPath: tmp, toPath: path)
    }

    func deleteFileIfExists(_ path: String) throws {
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }

    func firstNonEmptyPath(fallback: String, _ values: String?...) -> String {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return fallback
    }

    // MARK: - Meta

    func ensureAccountMeta(account: String, paths: PathContext) throws -> AccountMeta {
        if let existing = readAccountMeta(account: account, paths: paths) {
            return existing
        }

        let meta = AccountMeta(createdAt: Self.nowISO(), lastUsedAt: nil, lastLoginStatus: nil, lastLoginCheckedAt: nil, updatedAt: Self.nowISO())
        try writeAccountMeta(account: account, meta: meta, paths: paths)
        return meta
    }

    func readAccountMeta(account: String, paths: PathContext) -> AccountMeta? {
        let path = paths.accountMetaPath(account)
        guard let data = readFileIfExists(path) else { return nil }
        return try? decoder.decode(AccountMeta.self, from: data)
    }

    func writeAccountMeta(account: String, meta: AccountMeta, paths: PathContext) throws {
        let path = paths.accountMetaPath(account)
        try createDirectory(path: (path as NSString).deletingLastPathComponent, mode: 0o700)
        let data = try encoder.encode(meta)
        try writeFileAtomic(data: data + Data("\n".utf8), path: path, mode: 0o600)
    }

    @discardableResult
    func updateAccountMeta(account: String, paths: PathContext, mutate: (inout AccountMeta) -> Void) throws -> AccountMeta {
        var meta = readAccountMeta(account: account, paths: paths)
            ?? AccountMeta(createdAt: Self.nowISO(), lastUsedAt: nil, lastLoginStatus: nil, lastLoginCheckedAt: nil, updatedAt: nil)
        mutate(&meta)
        meta.updatedAt = Self.nowISO()
        try writeAccountMeta(account: account, meta: meta, paths: paths)
        return meta
    }

    // MARK: - Auth lock and auth swap

    func acquireAuthLock(account: String, force: Bool, paths: PathContext) throws -> AuthLockHandle {
        try createDirectory(path: paths.locksDir, mode: 0o700)
        let lockDir = paths.authLockDir
        let owner = AuthLockOwner(pid: getpid(), startedAt: Self.nowISO(), account: account)

        while true {
            let mkdirResult = lockDir.withCString { ptr in
                mkdir(ptr, S_IRWXU)
            }

            if mkdirResult == 0 {
                let handle = AuthLockHandle(lockDir: lockDir)
                try writeOwner(owner, lockDir: lockDir)
                return handle
            }

            if errno != EEXIST {
                throw CodexAccountServiceError(message: "Failed to acquire auth lock (errno \(errno)).")
            }

            let existing = readOwner(lockDir: lockDir)
            if let existing, !isPidRunning(existing.pid) {
                try? fileManager.removeItem(atPath: lockDir)
                continue
            }

            if force {
                try? fileManager.removeItem(atPath: lockDir)
                continue
            }

            let who: String
            if let existing {
                who = "\(existing.account) (pid \(existing.pid), started \(existing.startedAt))"
            } else {
                who = "unknown owner"
            }

            throw CodexAccountServiceError(message: "Auth swap is locked by \(who). Close the other session and retry.")
        }
    }

    func readOwner(lockDir: String) -> AuthLockOwner? {
        let path = (lockDir as NSString).appendingPathComponent("owner.json")
        guard let data = readFileIfExists(path) else { return nil }
        return try? decoder.decode(AuthLockOwner.self, from: data)
    }

    func writeOwner(_ owner: AuthLockOwner, lockDir: String) throws {
        let path = (lockDir as NSString).appendingPathComponent("owner.json")
        let data = try encoder.encode(owner)
        try writeFileAtomic(data: data + Data("\n".utf8), path: path, mode: 0o600)
    }

    func isPidRunning(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    func withAccountAuth<T>(
        account: String,
        forceLock: Bool,
        restorePreviousAuth: Bool,
        paths: PathContext,
        body: () throws -> T
    ) throws -> T {
        let lock = try acquireAuthLock(account: account, force: forceLock, paths: paths)
        defer { lock.release() }

        let defaultAuthPath = paths.defaultCodexAuthPath
        let previousAuth = restorePreviousAuth ? readFileIfExists(defaultAuthPath) : nil

        try setDefaultAuthFromAccount(account: account, paths: paths)
        let restoreDefaultAuth = {
            try self.restoreDefaultAuth(previousAuth, defaultAuthPath: defaultAuthPath)
        }

        do {
            let result = try body()
            try snapshotDefaultAuthToAccount(account: account, paths: paths)
            if restorePreviousAuth {
                try restoreDefaultAuth()
            }
            return result
        } catch {
            if restorePreviousAuth {
                try? restoreDefaultAuth()
            }
            throw error
        }
    }

    func applyAccountAuthToDefault(account: String, forceLock: Bool, paths: PathContext) throws {
        let lock = try acquireAuthLock(account: account, force: forceLock, paths: paths)
        defer { lock.release() }
        try setDefaultAuthFromAccount(account: account, paths: paths)
    }

    func setDefaultAuthFromAccount(account: String, paths: PathContext) throws {
        try syncAuthFile(from: paths.accountAuthPath(account), to: paths.defaultCodexAuthPath)
    }

    func snapshotDefaultAuthToAccount(account: String, paths: PathContext) throws {
        try syncAuthFile(
            from: paths.defaultCodexAuthPath,
            to: paths.accountAuthPath(account),
            destinationDirectory: paths.accountDir(account)
        )
    }

    func restoreDefaultAuth(_ previousAuth: Data?, defaultAuthPath: String) throws {
        if let previousAuth {
            try writeFileAtomic(data: previousAuth, path: defaultAuthPath, mode: 0o600)
        } else {
            try deleteFileIfExists(defaultAuthPath)
        }
    }

    func syncAuthFile(from source: String, to destination: String, destinationDirectory: String? = nil) throws {
        try AccountAuthCoordinator.syncAuthFile(
            fileManager: fileManager,
            sourcePath: source,
            destinationPath: destination,
            destinationDirectory: destinationDirectory,
            writeFile: { data, path, mode in
                try self.writeFileAtomic(data: data, path: path, mode: mode)
            },
            deleteFile: { path in
                try self.deleteFileIfExists(path)
            },
            createDirectory: { path, mode in
                try self.createDirectory(path: path, mode: mode)
            }
        )
    }

    // MARK: - Limits cache

    func getCachedLimits(account: String, ttlMs: Double, paths: PathContext) throws -> (snapshot: RateLimitSnapshot, ageMs: Double)? {
        let cache = try loadLimitsCache(paths: paths)
        guard let entry = cache.accounts[account] else { return nil }
        let nowMs = Date().timeIntervalSince1970 * 1000
        let ageMs = nowMs - entry.fetchedAt
        if ageMs > ttlMs {
            return nil
        }
        return (snapshot: entry.snapshot, ageMs: ageMs)
    }

    func setCachedLimits(account: String, snapshot: RateLimitSnapshot, provider: String, paths: PathContext) throws {
        var cache = try loadLimitsCache(paths: paths)
        cache.accounts[account] = LimitsCacheEntry(
            snapshot: snapshot,
            fetchedAt: Date().timeIntervalSince1970 * 1000,
            provider: provider
        )
        try saveLimitsCache(cache, paths: paths)
    }

    func loadLimitsCache(paths: PathContext) throws -> LimitsCacheFile {
        LimitsCacheStore.decode(
            data: readFileIfExists(paths.limitsCachePath),
            decoder: decoder,
            defaultVersion: 1
        )
    }

    func saveLimitsCache(_ cache: LimitsCacheFile, paths: PathContext) throws {
        let data = try LimitsCacheStore.encode(cache, encoder: encoder)
        try writeFileAtomic(data: data + Data("\n".utf8), path: paths.limitsCachePath, mode: 0o600)
    }

    // MARK: - Utils

    static func nowISO() -> String {
        nowFormatter.string(from: Date())
    }

    /// Proactively refresh tokens for all accounts with aging auth.
    /// Called during background refresh cycles, before fetching usage.
    func refreshStaleTokens() -> [String: Error] {
        let paths = currentPaths()
        guard let config = try? loadConfig(paths: paths) else {
            return [:]
        }

        var errors: [String: Error] = [:]
        for account in config.accounts {
            let authPath = paths.accountAuthPath(account)
            guard var payload = try? loadAuthPayload(from: authPath) else {
                continue
            }
            guard shouldRefreshToken(payload) else {
                continue
            }

            MultiCodexLog.log(
                .auth,
                level: .debug,
                "Proactively refreshing token for \(account)"
            )

            do {
                if let refreshed = try refreshAccessToken(authPayload: &payload, authPath: authPath) {
                    MultiCodexLog.log(
                        .auth,
                        level: .info,
                        "Token refreshed for \(account)",
                        metadata: ["refreshed": "yes"]
                    )
                }
            } catch {
                errors[account] = error
                MultiCodexLog.log(
                    .auth,
                    level: .error,
                    "Token refresh failed for \(account): \(error.localizedDescription)"
                )
            }
        }
        return errors
    }

    func validatedAccountName(_ name: String) throws -> String {
        let account = normalizeAccountName(name)
        guard isValidAccountName(account) else {
            throw CodexAccountServiceError(message: "Invalid account name. Use letters, numbers, underscore, dash, dot, or @.")
        }
        return account
    }

    func normalizeAccountName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isValidAccountName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.range(of: "^[a-zA-Z0-9][a-zA-Z0-9_.@-]*$", options: .regularExpression) != nil
    }

    func shellQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

}
