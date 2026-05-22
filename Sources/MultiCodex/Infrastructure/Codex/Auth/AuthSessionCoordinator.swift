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
        let data = readFileIfExists(paths.configPath)
        do {
            return try AccountConfigStore.decodeConfig(from: data)
        } catch {
            var recovered = recoverConfigFromAccountStorage(paths: paths)
            let configMetadata = recoverConfigMetadata(from: data)
            recovered.accounts.formUnion(configMetadata.accounts)
            if let currentAccount = configMetadata.currentAccount,
               recovered.accounts.contains(currentAccount)
            {
                recovered.currentAccount = currentAccount
            }
            guard !recovered.accounts.isEmpty else {
                throw error
            }
            backupInvalidConfigIfPossible(paths: paths)
            MultiCodexLog.log(
                .config,
                level: .error,
                "Recovered account registry from stored account directories after config decode failed",
                metadata: ["accounts": "\(recovered.accounts.count)"]
            )
            return recovered
        }
    }

    func saveConfig(_ config: NativeConfig, paths: PathContext) throws {
        let data = try AccountConfigStore.encodeConfig(config)
        try writeFileAtomic(data: data + Data("\n".utf8), path: paths.configPath, mode: 0o600)
    }

    func withConfigMutationLock<T>(_ body: () throws -> T) rethrows -> T {
        configMutationLock.lock()
        defer { configMutationLock.unlock() }
        return try body()
    }

    func recoverConfigFromAccountStorage(paths: PathContext) -> NativeConfig {
        var accounts: Set<String> = []

        appendValidAccountDirectories(atPath: paths.accountsDir, into: &accounts)
        let managedHomesPath = ManagedCodexHomeFactory.scopedRootURL(multicodexHome: paths.multicodexHome).path
        appendValidAccountDirectories(atPath: managedHomesPath, into: &accounts)

        return AccountConfigRecord(currentAccount: nil, accounts: accounts)
    }

    private func recoverConfigMetadata(from data: Data?) -> NativeConfig {
        var accounts: Set<String> = []
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return AccountConfigRecord(currentAccount: nil, accounts: [])
        }

        if let accountMap = object["accounts"] as? [String: Any] {
            for name in accountMap.keys {
                let normalized = normalizeAccountName(name)
                guard isValidAccountName(normalized) else {
                    continue
                }
                accounts.insert(normalized)
            }
        }

        let currentAccount: String?
        if let current = object["currentAccount"] as? String {
            let normalized = normalizeAccountName(current)
            currentAccount = isValidAccountName(normalized) ? normalized : nil
        } else {
            currentAccount = nil
        }

        return AccountConfigRecord(currentAccount: currentAccount, accounts: accounts)
    }

    private func appendValidAccountDirectories(atPath rootPath: String, into accounts: inout Set<String>) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: rootPath) else {
            return
        }

        for name in names {
            let path = (rootPath as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  isValidAccountName(name)
            else {
                continue
            }
            accounts.insert(name)
        }
    }

    private func backupInvalidConfigIfPossible(paths: PathContext) {
        guard fileManager.fileExists(atPath: paths.configPath) else {
            return
        }

        let backupPath = "\(paths.configPath).invalid-\(Self.nowISO().replacingOccurrences(of: ":", with: "-"))"
        guard !fileManager.fileExists(atPath: backupPath) else {
            return
        }
        try? fileManager.copyItem(atPath: paths.configPath, toPath: backupPath)
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

        // Use POSIX rename() for true atomic replacement. Unlike FileManager's
        // removeItem + moveItem sequence, rename() is a single atomic syscall
        // that replaces the destination without a window where the file is absent.
        let result = tmp.withCString { src in
            path.withCString { dst in
                Darwin.rename(src, dst)
            }
        }
        if result != 0 {
            // Fallback: remove + move (for cross-device scenarios, though unusual)
            try? fileManager.removeItem(atPath: tmp)
            throw CodexAccountServiceError(message: "Atomic rename failed for \(path) (errno \(errno)).")
        }
    }

    func deleteFileIfExists(_ path: String) throws {
        do {
            try fileManager.removeItem(atPath: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // Already absent — not an error.
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

        MultiCodexLog.log(
            .auth,
            level: .debug,
            "Acquiring auth lock for \(account)",
            metadata: ["force": force ? "yes" : "no"]
        )

        var retryCount = 0
        let maxRetries = 50

        while retryCount < maxRetries {
            retryCount += 1
            let mkdirResult = lockDir.withCString { ptr in
                mkdir(ptr, S_IRWXU)
            }

            if mkdirResult == 0 {
                let handle = AuthLockHandle(lockDir: lockDir)
                try writeOwner(owner, lockDir: lockDir)
                MultiCodexLog.log(
                    .auth,
                    level: .debug,
                    "Auth lock acquired for \(account)"
                )
                return handle
            }

            if errno != EEXIST {
                throw CodexAccountServiceError(message: "Failed to acquire auth lock (errno \(errno)).")
            }

            let existing = readOwner(lockDir: lockDir)
            if let existing, !isPidRunning(existing.pid) {
                MultiCodexLog.log(
                    .auth,
                    level: .info,
                    "Removing stale auth lock from dead process",
                    metadata: [
                        "stalePid": "\(existing.pid)",
                        "staleAccount": existing.account,
                        "staleStartedAt": existing.startedAt,
                    ]
                )
                try? fileManager.removeItem(atPath: lockDir)
                continue
            }

            if force {
                MultiCodexLog.log(
                    .auth,
                    level: .info,
                    "Force-removing auth lock held by \(existing?.account ?? "unknown")",
                    metadata: ["existingPid": existing.map { "\($0.pid)" } ?? "unknown"]
                )
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

        throw CodexAccountServiceError(message: "Failed to acquire auth lock for \(account) after \(maxRetries) attempts.")
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
        MultiCodexLog.log(
            .auth,
            level: .debug,
            "withAccountAuth: swapping auth for \(account)",
            metadata: ["restorePrevious": restorePreviousAuth ? "yes" : "no"]
        )

        let lock = try acquireAuthLock(account: account, force: forceLock, paths: paths)
        defer { lock.release() }

        let defaultAuthPath = paths.defaultCodexAuthPath
        let previousAuth = restorePreviousAuth ? readFileIfExists(defaultAuthPath) : nil

        try setDefaultAuthFromAccount(account: account, paths: paths)
        let expectedAccountAuth = readFileIfExists(defaultAuthPath)
        let restoreDefaultAuth = {
            try self.restoreDefaultAuth(previousAuth, defaultAuthPath: defaultAuthPath)
        }

        do {
            let result = try body()
            try verifyDefaultAuthMatchesAccount(
                account: account,
                expectedAccountAuth: expectedAccountAuth,
                currentDefaultAuth: readFileIfExists(defaultAuthPath)
            )
            try snapshotDefaultAuthToAccount(account: account, paths: paths)
            if restorePreviousAuth {
                try restoreDefaultAuth()
            }
            MultiCodexLog.log(
                .auth,
                level: .debug,
                "withAccountAuth: completed for \(account)"
            )
            return result
        } catch {
            MultiCodexLog.log(
                .auth,
                level: .error,
                "withAccountAuth: failed for \(account): \(error.localizedDescription)"
            )
            if restorePreviousAuth {
                try? restoreDefaultAuth()
            }
            throw error
        }
    }

    private func verifyDefaultAuthMatchesAccount(
        account: String,
        expectedAccountAuth: Data?,
        currentDefaultAuth: Data?
    ) throws {
        guard let expectedAccountAuth else {
            return
        }
        guard let currentDefaultAuth else {
            throw AuthSwapService.AuthSwapError.externalAuthDetected(
                previousAccount: account,
                previousIdentity: resolveAuthIdentity(from: expectedAccountAuth),
                systemIdentity: nil
            )
        }
        if authIdentityMatches(currentDefaultAuth, expectedAccountAuth) {
            return
        }
        throw AuthSwapService.AuthSwapError.externalAuthDetected(
            previousAccount: account,
            previousIdentity: resolveAuthIdentity(from: expectedAccountAuth),
            systemIdentity: resolveAuthIdentity(from: currentDefaultAuth)
        )
    }

    private func authIdentityMatches(_ lhs: Data, _ rhs: Data) -> Bool {
        let leftIdentity = resolveAccountIdentity(from: lhs)
        let rightIdentity = resolveAccountIdentity(from: rhs)
        if AccountIdentityMatcher.matches(leftIdentity, rightIdentity) {
            return true
        }
        return lhs == rhs
    }

    private func resolveAccountIdentity(from data: Data) -> AccountIdentity {
        guard let resolved = resolveAuthIdentity(from: data) else {
            return .unresolved
        }
        return AccountIdentityResolver.resolve(accountId: resolved.accountId, email: resolved.email)
    }

    private func resolveAuthIdentity(from data: Data) -> ResolvedAccountIdentity? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return resolveFromAuthPayload(payload)
    }

    func applyAccountAuthToDefault(account: String, forceLock: Bool, paths: PathContext) throws {
        let lock = try acquireAuthLock(account: account, force: forceLock, paths: paths)
        defer { lock.release() }
        try AuthSwapService.switchToAccount(
            named: account,
            previousAccountName: nil,
            paths: paths
        )
    }

    func setDefaultAuthFromAccount(account: String, paths: PathContext) throws {
        if let managedAuthPath = managedAuthPath(for: account, paths: paths) {
            try syncAuthFile(from: managedAuthPath, to: paths.defaultCodexAuthPath)
            return
        }
        try syncAuthFile(from: paths.accountAuthPath(account), to: paths.defaultCodexAuthPath)
    }

    func snapshotDefaultAuthToAccount(account: String, paths: PathContext) throws {
        try syncAuthFile(
            from: paths.defaultCodexAuthPath,
            to: paths.accountAuthPath(account),
            destinationDirectory: paths.accountDir(account)
        )
        if let managedHome = managedHomeForMutatingAuth(account: account, paths: paths),
           let authData = readFileIfExists(paths.defaultCodexAuthPath)
        {
            try ManagedCodexHomeFactory.writeAuthData(authData, to: managedHome)
        }
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

    func isManagedHomeMigrationComplete(paths: PathContext) -> Bool {
        let markerURL = URL(fileURLWithPath: paths.multicodexHome)
            .appendingPathComponent(".managed-migration-complete")
        return fileManager.fileExists(atPath: markerURL.path)
    }

    func managedHomeForMutatingAuth(account: String, paths: PathContext) -> URL? {
        guard isManagedHomeMigrationComplete(paths: paths) else { return nil }
        return try? ManagedCodexHomeFactory.createHome(for: account, multicodexHome: paths.multicodexHome)
    }

    func managedAuthPath(for account: String, paths: PathContext) -> String? {
        guard isManagedHomeMigrationComplete(paths: paths),
              let home = ManagedCodexHomeFactory.homeURL(for: account, multicodexHome: paths.multicodexHome),
              fileManager.fileExists(atPath: home.appendingPathComponent("auth.json").path)
        else {
            return nil
        }
        return home.appendingPathComponent("auth.json").path
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
    func refreshStaleTokensNow() -> [String: Error] {
        let paths = currentPaths()
        guard let config = try? loadConfig(paths: paths) else {
            return [:]
        }

        var errors: [String: Error] = [:]
        for account in config.accounts {
            let legacyAuthPath = paths.accountAuthPath(account)
            let authPath = managedAuthPath(for: account, paths: paths) ?? legacyAuthPath
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
                if try refreshAccessToken(authPayload: &payload, authPath: authPath) != nil {
                    if authPath != legacyAuthPath,
                       let refreshedData = readFileIfExists(authPath)
                    {
                        try writeFileAtomic(data: refreshedData, path: legacyAuthPath, mode: 0o600)
                    }
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

    func refreshStaleTokens() async -> [String: Error] {
        await Task.detached(priority: .utility) { [self] in
            refreshStaleTokensNow()
        }.value
    }

    func refreshStaleTokens() -> [String: Error] {
        refreshStaleTokensNow()
    }

    func storedAuthModifiedDate(for account: String, paths: PathContext) -> Date? {
        let authPath = managedAuthPath(for: account, paths: paths) ?? paths.accountAuthPath(account)
        return try? fileManager.attributesOfItem(atPath: authPath)[.modificationDate] as? Date
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
