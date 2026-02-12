import Darwin
import Foundation

final class MultiCodexCLI {
    static let limitsCacheTTLSeconds = 300
    private static let nowFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private struct NativeConfig {
        var currentAccount: String?
        var accounts: Set<String>
    }

    private struct AccountMeta: Codable {
        var createdAt: String
        var lastUsedAt: String?
        var lastLoginStatus: String?
        var lastLoginCheckedAt: String?
        var updatedAt: String?
    }

    private struct AuthLockOwner: Codable {
        let pid: Int32
        let startedAt: String
        let account: String
    }

    private final class AuthLockHandle {
        private let lockDir: String
        private let fileManager = FileManager.default

        init(lockDir: String) {
            self.lockDir = lockDir
        }

        func release() {
            try? fileManager.removeItem(atPath: lockDir)
        }
    }

    private struct LimitsCacheEntry: Codable {
        let snapshot: RateLimitSnapshot
        let fetchedAt: Double
        let provider: String?
    }

    private struct LimitsCacheFile: Codable {
        var version: Int
        var accounts: [String: LimitsCacheEntry]
    }

    private struct CodexRuntime {
        let executableURL: URL
        let prefixArguments: [String]
        let display: String
    }

    private enum ExistingAccountBehavior {
        case ignore
        case fail
    }

    private struct PathContext {
        let homeDir: String
        let multicodexHome: String

        var configPath: String { (multicodexHome as NSString).appendingPathComponent("config.json") }
        var accountsDir: String { (multicodexHome as NSString).appendingPathComponent("accounts") }
        var locksDir: String { (multicodexHome as NSString).appendingPathComponent("locks") }
        var authLockDir: String { (locksDir as NSString).appendingPathComponent("auth.lockdir") }
        var limitsCachePath: String { (multicodexHome as NSString).appendingPathComponent("limits-cache.json") }
        var defaultCodexHome: String { (homeDir as NSString).appendingPathComponent(".codex") }
        var defaultCodexAuthPath: String { (defaultCodexHome as NSString).appendingPathComponent("auth.json") }

        func accountDir(_ account: String) -> String {
            (accountsDir as NSString).appendingPathComponent(account)
        }

        func accountAuthPath(_ account: String) -> String {
            (accountDir(account) as NSString).appendingPathComponent("auth.json")
        }

        func accountMetaPath(_ account: String) -> String {
            (accountDir(account) as NSString).appendingPathComponent("meta.json")
        }
    }

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // Kept for backward compatibility with existing settings key.
    // This now points to a codex executable path/name (not Node).
    var customNodePath: String?
    var sandboxHomeDirectory: String?
    var sandboxMulticodexHomeDirectory: String?

    private(set) var resolutionHint: String?

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func fetchAccounts() async throws -> AccountsListPayload {
        try fetchAccountsNow()
    }

    func fetchLimits(refreshLive: Bool) async throws -> LimitsPayload {
        try fetchLimitsNow(refreshLive: refreshLive)
    }

    func switchAccount(name: String) async throws {
        _ = try switchAccountNow(name: name)
    }

    func addAccount(name: String) async throws -> AddAccountPayload {
        try addAccountNow(name: name)
    }

    func removeAccount(name: String, deleteData: Bool) async throws -> RemoveAccountPayload {
        try removeAccountNow(name: name, deleteData: deleteData)
    }

    func renameAccount(from oldName: String, to newName: String) async throws -> RenameAccountPayload {
        try renameAccountNow(from: oldName, to: newName)
    }

    func importDefaultAuth(into name: String) async throws -> ImportAccountPayload {
        try importDefaultAuthNow(into: name)
    }

    func fetchStatus(name: String) async throws -> AccountStatusPayload {
        try fetchStatusNow(name: name)
    }

    func openLoginInTerminal(account name: String) throws {
        _ = try switchAccountNow(name: name)
        let command = try makeTerminalCodexLoginCommand(profileName: name, firstTime: false)
        try launchTerminal(script: command)
    }

    func openNewProfileLoginInTerminal(newProfileName name: String) throws {
        _ = try addAccountIfNeededNow(name: name)
        _ = try switchAccountNow(name: name)
        let command = try makeTerminalCodexLoginCommand(profileName: name, firstTime: true)
        try launchTerminal(script: command)
    }

    func effectiveMulticodexHomePath() -> String {
        currentPaths().multicodexHome
    }

    // MARK: - Accounts

    private func fetchAccountsNow() throws -> AccountsListPayload {
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

    private func addAccountIfNeededNow(name: String) throws -> AddAccountPayload {
        try addAccountCore(name: name, onExisting: .ignore)
    }

    private func addAccountNow(name: String) throws -> AddAccountPayload {
        try addAccountCore(name: name, onExisting: .fail)
    }

    private func addAccountCore(name: String, onExisting: ExistingAccountBehavior) throws -> AddAccountPayload {
        let account = try validatedAccountName(name)
        let paths = currentPaths()
        var config = try loadConfig(paths: paths)

        if config.accounts.contains(account) {
            if onExisting == .fail {
                throw MultiCodexCLIError(message: "Account already exists: \(account)")
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

    private func switchAccountNow(name: String) throws -> SwitchAccountPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        var config = try loadConfig(paths: paths)

        guard config.accounts.contains(account) else {
            throw MultiCodexCLIError(message: "Unknown account: \(account)")
        }

        try applyAccountAuthToDefault(account: account, forceLock: false, paths: paths)

        config.currentAccount = account
        try saveConfig(config, paths: paths)
        _ = try updateAccountMeta(account: account, paths: paths) { meta in
            meta.lastUsedAt = Self.nowISO()
        }

        return SwitchAccountPayload(currentAccount: account)
    }

    private func removeAccountNow(name: String, deleteData: Bool) throws -> RemoveAccountPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        var config = try loadConfig(paths: paths)

        guard config.accounts.contains(account) else {
            throw MultiCodexCLIError(message: "Unknown account: \(account)")
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

    private func renameAccountNow(from oldName: String, to newName: String) throws -> RenameAccountPayload {
        let source = normalizeAccountName(oldName)
        let target = try validatedAccountName(newName)

        let paths = currentPaths()
        var config = try loadConfig(paths: paths)

        guard config.accounts.contains(source) else {
            throw MultiCodexCLIError(message: "Unknown account: \(source)")
        }
        guard !config.accounts.contains(target) else {
            throw MultiCodexCLIError(message: "Account already exists: \(target)")
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

    private func importDefaultAuthNow(into name: String) throws -> ImportAccountPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        let config = try loadConfig(paths: paths)
        guard config.accounts.contains(account) else {
            throw MultiCodexCLIError(message: "Unknown account: \(account)")
        }

        let lock = try acquireAuthLock(account: account, force: false, paths: paths)
        defer { lock.release() }

        try snapshotDefaultAuthToAccount(account: account, paths: paths)
        _ = try updateAccountMeta(account: account, paths: paths) { meta in
            meta.lastUsedAt = Self.nowISO()
        }

        return ImportAccountPayload(account: account)
    }

    // MARK: - Status and Limits

    private func fetchStatusNow(name: String) throws -> AccountStatusPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        let config = try loadConfig(paths: paths)
        guard config.accounts.contains(account) else {
            throw MultiCodexCLIError(message: "Unknown account: \(account)")
        }

        let result = try withAccountAuth(account: account, forceLock: false, restorePreviousAuth: true, paths: paths) {
            try runCodexCapture(arguments: ["login", "status"])
        }

        let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try updateAccountMeta(account: account, paths: paths) { meta in
            meta.lastUsedAt = Self.nowISO()
            meta.lastLoginStatus = combined.isEmpty ? nil : combined
            meta.lastLoginCheckedAt = Self.nowISO()
        }

        return AccountStatusPayload(
            account: account,
            exitCode: Int(result.exitCode),
            stdout: result.stdout,
            stderr: result.stderr,
            output: combined,
            checkedAt: Self.nowISO()
        )
    }

    private func fetchLimitsNow(refreshLive: Bool) throws -> LimitsPayload {
        let paths = currentPaths()
        let config = try loadConfig(paths: paths)
        let targets = config.accounts.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var results: [LimitsResult] = []
        var errors: [LimitsErrorEntry] = []

        for account in targets {
            do {
                if !refreshLive, let cached = try getCachedLimits(account: account, ttlMs: Double(Self.limitsCacheTTLSeconds * 1000), paths: paths) {
                    let ageSec = Int((cached.ageMs / 1000.0).rounded())
                    results.append(
                        LimitsResult(
                            account: account,
                            source: "cached",
                            snapshot: cached.snapshot,
                            ageSec: ageSec
                        )
                    )
                    continue
                }

                let snapshot = try withAccountAuth(account: account, forceLock: false, restorePreviousAuth: true, paths: paths) {
                    try fetchRateLimitsViaRpc()
                }

                try setCachedLimits(account: account, snapshot: snapshot, provider: "rpc", paths: paths)

                results.append(
                    LimitsResult(
                        account: account,
                        source: "live-rpc",
                        snapshot: snapshot,
                        ageSec: nil
                    )
                )
            } catch {
                errors.append(LimitsErrorEntry(account: account, message: error.localizedDescription))
            }
        }

        return LimitsPayload(results: results, errors: errors)
    }

    private func fetchRateLimitsViaRpc() throws -> RateLimitSnapshot {
        let runtime = try resolveCodexRuntime()
        let process = Process()
        process.executableURL = runtime.executableURL
        process.arguments = runtime.prefixArguments + ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.environment = baseEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw MultiCodexCLIError(message: "Could not run \(runtime.display): \(error.localizedDescription)")
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdinHandle = stdinPipe.fileHandleForWriting

        let responseSemaphore = DispatchSemaphore(value: 0)
        let stateLock = NSLock()

        var stdoutBuffer = ""
        var stderrBuffer = ""
        var didSignal = false
        var responseMessage: [String: Any]?
        var responseError: String?

        func signalOnce() {
            stateLock.lock()
            defer { stateLock.unlock() }
            if !didSignal {
                didSignal = true
                responseSemaphore.signal()
            }
        }

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let text = String(data: data, encoding: .utf8) ?? ""

            stateLock.lock()
            stdoutBuffer += text
            while let nl = stdoutBuffer.firstIndex(of: "\n") {
                let line = String(stdoutBuffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutBuffer = String(stdoutBuffer[stdoutBuffer.index(after: nl)...])
                guard !line.isEmpty else { continue }

                guard let raw = line.data(using: .utf8),
                      let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
                else {
                    continue
                }

                let id = payload["id"] as? Int
                if id == 2 {
                    if let err = payload["error"] as? [String: Any], let message = err["message"] as? String {
                        responseError = message
                    } else {
                        responseMessage = payload
                    }
                    if !didSignal {
                        didSignal = true
                        responseSemaphore.signal()
                    }
                }
            }
            stateLock.unlock()
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            stateLock.lock()
            stderrBuffer += text
            stateLock.unlock()
        }

        do {
            try writeRpcMessage(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "multicodex-mac", "version": "native"]]], to: stdinHandle)
            try writeRpcMessage(["method": "initialized", "params": [:]], to: stdinHandle)
            try writeRpcMessage(["id": 2, "method": "account/rateLimits/read", "params": [:]], to: stdinHandle)
        } catch {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw MultiCodexCLIError(message: "Could not write Codex RPC request: \(error.localizedDescription)")
        }

        let waitResult = responseSemaphore.wait(timeout: .now() + 12)

        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        try? stdinHandle.close()

        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        if waitResult == .timedOut {
            let stderrText = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                throw MultiCodexCLIError(message: "Codex RPC timed out while fetching rate limits.")
            }
            throw MultiCodexCLIError(message: "Codex RPC timed out: \(stderrText)")
        }

        if let responseError, !responseError.isEmpty {
            throw MultiCodexCLIError(message: "Codex RPC error: \(responseError)")
        }

        guard let message = responseMessage else {
            let stderrText = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                throw MultiCodexCLIError(message: "Codex RPC returned no response.")
            }
            throw MultiCodexCLIError(message: stderrText)
        }

        let result = message["result"] as? [String: Any]
        let rateLimitsValue = result?["rateLimits"]

        if rateLimitsValue is NSNull || rateLimitsValue == nil {
            return RateLimitSnapshot(primary: nil, secondary: nil, credits: nil)
        }

        guard let rateLimitsObject = rateLimitsValue as? [String: Any] else {
            throw MultiCodexCLIError(message: "Unexpected Codex RPC payload for rate limits.")
        }

        let data = try JSONSerialization.data(withJSONObject: rateLimitsObject, options: [])
        return try decoder.decode(RateLimitSnapshot.self, from: data)
    }

    private func writeRpcMessage(_ payload: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        handle.write(data)
        if let newline = "\n".data(using: .utf8) {
            handle.write(newline)
        }
    }

    // MARK: - Terminal login

    private func launchTerminal(script: String) throws {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(escaped)\"",
        ]

        do {
            try process.run()
        } catch {
            throw MultiCodexCLIError(message: "Could not open Terminal for login: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MultiCodexCLIError(message: "Could not launch Terminal login session (exit \(process.terminationStatus)).")
        }
    }

    private func makeTerminalCodexLoginCommand(profileName: String, firstTime: Bool) throws -> String {
        let appName = shellQuote("MultiCodex")
        let profile = shellQuote(profileName)
        let codexLoginCommand = try makeCodexShellCommand(arguments: ["login"])

        var lines = terminalPreambleLines()
        if firstTime {
            lines.append("echo \"Starting first-time MultiCodex login...\"")
            lines.append("echo \"Profile \(profile) is ready and can be renamed later in Settings.\"")
        } else {
            lines.append("echo \"Starting MultiCodex login flow for \(profile)...\"")
        }
        lines.append(codexLoginCommand)
        lines.append("LOGIN_EXIT=$?")
        lines.append("if [ \"$LOGIN_EXIT\" -eq 0 ]; then")
        lines.append("  echo \"Login completed.\"")
        lines.append("else")
        lines.append("  echo \"Login failed (exit $LOGIN_EXIT).\"")
        lines.append("fi")
        lines.append("open -a \(appName) >/dev/null 2>&1 || true")
        lines.append("exit $LOGIN_EXIT")

        return lines.joined(separator: "\n")
    }

    // MARK: - Runtime and process

    private func resolveCodexRuntime() throws -> CodexRuntime {
        func runtimeForRaw(_ raw: String, source: String) throws -> CodexRuntime {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw MultiCodexCLIError(message: "Empty runtime value for \(source).")
            }
            if trimmed.contains("/") {
                let expanded = (trimmed as NSString).expandingTildeInPath
                if fileManager.isExecutableFile(atPath: expanded) {
                    return CodexRuntime(executableURL: URL(fileURLWithPath: expanded), prefixArguments: [], display: "\(expanded) [\(source)]")
                }
                throw MultiCodexCLIError(message: "Configured codex executable is not executable: \(expanded)")
            }
            return CodexRuntime(executableURL: URL(fileURLWithPath: "/usr/bin/env"), prefixArguments: [trimmed], display: "\(trimmed) (from PATH, \(source))")
        }

        if let custom = customNodePath?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            // Migration guard: ignore old Node path values if present.
            let lower = custom.lowercased()
            if !lower.hasSuffix("/node") && lower != "node" {
                let runtime = try runtimeForRaw(custom, source: "custom")
                updateResolutionHint(runtime: runtime)
                return runtime
            }
        }

        if let envRaw = ProcessInfo.processInfo.environment["MULTICODEX_CODEX"], !envRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let runtime = try runtimeForRaw(envRaw, source: "MULTICODEX_CODEX")
            updateResolutionHint(runtime: runtime)
            return runtime
        }

        let knownPaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ]

        for codexPath in knownPaths where fileManager.isExecutableFile(atPath: codexPath) {
            let runtime = CodexRuntime(executableURL: URL(fileURLWithPath: codexPath), prefixArguments: [], display: codexPath)
            updateResolutionHint(runtime: runtime)
            return runtime
        }

        let runtime = CodexRuntime(executableURL: URL(fileURLWithPath: "/usr/bin/env"), prefixArguments: ["codex"], display: "codex (from PATH)")
        updateResolutionHint(runtime: runtime)
        return runtime
    }

    private func updateResolutionHint(runtime: CodexRuntime) {
        var hint = "Codex runtime: \(runtime.display)"
        let paths = currentPaths()
        hint += " | HOME: \(paths.homeDir)"
        hint += " | MULTICODEX_HOME: \(paths.multicodexHome)"
        resolutionHint = hint
    }

    private func runCodexCapture(arguments: [String]) throws -> ProcessResult {
        let runtime = try resolveCodexRuntime()
        let process = Process()
        process.executableURL = runtime.executableURL
        process.arguments = runtime.prefixArguments + arguments
        process.environment = baseEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw MultiCodexCLIError(message: "Could not run \(runtime.display): \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }

    private func makeCodexShellCommand(arguments: [String]) throws -> String {
        let runtime = try resolveCodexRuntime()
        let parts = [runtime.executableURL.path] + runtime.prefixArguments + arguments
        return parts.map(shellQuote).joined(separator: " ")
    }

    private func baseEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let existingPath = env["PATH"], !existingPath.contains("/opt/homebrew/bin") {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + existingPath
        }
        applySandboxEnvironment(to: &env)
        return env
    }

    private func applySandboxEnvironment(to env: inout [String: String]) {
        let paths = currentPaths()
        env["HOME"] = paths.homeDir
        env["MULTICODEX_HOME"] = paths.multicodexHome
    }

    private func terminalPreambleLines() -> [String] {
        let paths = currentPaths()
        return [
            "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"",
            "export HOME=\(shellQuote(paths.homeDir))",
            "export MULTICODEX_HOME=\(shellQuote(paths.multicodexHome))",
        ]
    }

    // MARK: - Config, paths, files

    private func currentPaths() -> PathContext {
        let processEnvironment = ProcessInfo.processInfo.environment
        let home = firstNonEmptyPath(
            fallback: NSHomeDirectory(),
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

    private func loadConfig(paths: PathContext) throws -> NativeConfig {
        guard let data = readFileIfExists(paths.configPath), !data.isEmpty else {
            return NativeConfig(currentAccount: nil, accounts: [])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return NativeConfig(currentAccount: nil, accounts: [])
        }

        if let version = json["version"] as? Int, (version == 1 || version == 2) {
            let current = json["currentAccount"] as? String
            let accountObjects = json["accounts"] as? [String: Any] ?? [:]
            return NativeConfig(currentAccount: current, accounts: Set(accountObjects.keys))
        }

        return NativeConfig(currentAccount: nil, accounts: [])
    }

    private func saveConfig(_ config: NativeConfig, paths: PathContext) throws {
        let accountsObject = Dictionary(uniqueKeysWithValues: config.accounts.sorted().map { ($0, [String: Any]()) })
        var root: [String: Any] = [
            "version": 2,
            "accounts": accountsObject,
        ]
        if let current = config.currentAccount {
            root["currentAccount"] = current
        }

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try writeFileAtomic(data: data + Data("\n".utf8), path: paths.configPath, mode: 0o600)
    }

    private func createDirectory(path: String, mode: Int16) throws {
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path)
    }

    private func readFileIfExists(_ path: String) -> Data? {
        return fileManager.contents(atPath: path)
    }

    private func writeFileAtomic(data: Data, path: String, mode: Int16) throws {
        let dir = (path as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            try createDirectory(path: dir, mode: 0o700)
        }

        let tmp = "\(path).tmp.\(UUID().uuidString)"
        guard fileManager.createFile(atPath: tmp, contents: data) else {
            throw MultiCodexCLIError(message: "Could not create temporary file at \(tmp).")
        }
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: tmp)

        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
        try fileManager.moveItem(atPath: tmp, toPath: path)
    }

    private func deleteFileIfExists(_ path: String) throws {
        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }

    private func firstNonEmptyPath(fallback: String, _ values: String?...) -> String {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return fallback
    }

    // MARK: - Meta

    private func ensureAccountMeta(account: String, paths: PathContext) throws -> AccountMeta {
        if let existing = readAccountMeta(account: account, paths: paths) {
            return existing
        }

        let meta = AccountMeta(createdAt: Self.nowISO(), lastUsedAt: nil, lastLoginStatus: nil, lastLoginCheckedAt: nil, updatedAt: Self.nowISO())
        try writeAccountMeta(account: account, meta: meta, paths: paths)
        return meta
    }

    private func readAccountMeta(account: String, paths: PathContext) -> AccountMeta? {
        let path = paths.accountMetaPath(account)
        guard let data = readFileIfExists(path) else { return nil }
        return try? decoder.decode(AccountMeta.self, from: data)
    }

    private func writeAccountMeta(account: String, meta: AccountMeta, paths: PathContext) throws {
        let path = paths.accountMetaPath(account)
        try createDirectory(path: (path as NSString).deletingLastPathComponent, mode: 0o700)
        let data = try encoder.encode(meta)
        try writeFileAtomic(data: data + Data("\n".utf8), path: path, mode: 0o600)
    }

    @discardableResult
    private func updateAccountMeta(account: String, paths: PathContext, mutate: (inout AccountMeta) -> Void) throws -> AccountMeta {
        var meta = readAccountMeta(account: account, paths: paths)
            ?? AccountMeta(createdAt: Self.nowISO(), lastUsedAt: nil, lastLoginStatus: nil, lastLoginCheckedAt: nil, updatedAt: nil)
        mutate(&meta)
        meta.updatedAt = Self.nowISO()
        try writeAccountMeta(account: account, meta: meta, paths: paths)
        return meta
    }

    // MARK: - Auth lock and auth swap

    private func acquireAuthLock(account: String, force: Bool, paths: PathContext) throws -> AuthLockHandle {
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
                throw MultiCodexCLIError(message: "Failed to acquire auth lock (errno \(errno)).")
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

            throw MultiCodexCLIError(message: "Auth swap is locked by \(who). Close the other session and retry.")
        }
    }

    private func readOwner(lockDir: String) -> AuthLockOwner? {
        let path = (lockDir as NSString).appendingPathComponent("owner.json")
        guard let data = readFileIfExists(path) else { return nil }
        return try? decoder.decode(AuthLockOwner.self, from: data)
    }

    private func writeOwner(_ owner: AuthLockOwner, lockDir: String) throws {
        let path = (lockDir as NSString).appendingPathComponent("owner.json")
        let data = try encoder.encode(owner)
        try writeFileAtomic(data: data + Data("\n".utf8), path: path, mode: 0o600)
    }

    private func isPidRunning(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private func withAccountAuth<T>(
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

    private func applyAccountAuthToDefault(account: String, forceLock: Bool, paths: PathContext) throws {
        let lock = try acquireAuthLock(account: account, force: forceLock, paths: paths)
        defer { lock.release() }
        try setDefaultAuthFromAccount(account: account, paths: paths)
    }

    private func setDefaultAuthFromAccount(account: String, paths: PathContext) throws {
        try syncAuthFile(from: paths.accountAuthPath(account), to: paths.defaultCodexAuthPath)
    }

    private func snapshotDefaultAuthToAccount(account: String, paths: PathContext) throws {
        try syncAuthFile(
            from: paths.defaultCodexAuthPath,
            to: paths.accountAuthPath(account),
            destinationDirectory: paths.accountDir(account)
        )
    }

    private func restoreDefaultAuth(_ previousAuth: Data?, defaultAuthPath: String) throws {
        if let previousAuth {
            try writeFileAtomic(data: previousAuth, path: defaultAuthPath, mode: 0o600)
        } else {
            try deleteFileIfExists(defaultAuthPath)
        }
    }

    private func syncAuthFile(from source: String, to destination: String, destinationDirectory: String? = nil) throws {
        if let data = readFileIfExists(source) {
            if let destinationDirectory {
                try createDirectory(path: destinationDirectory, mode: 0o700)
            }
            try writeFileAtomic(data: data, path: destination, mode: 0o600)
        } else {
            try deleteFileIfExists(destination)
        }
    }

    // MARK: - Limits cache

    private func getCachedLimits(account: String, ttlMs: Double, paths: PathContext) throws -> (snapshot: RateLimitSnapshot, ageMs: Double)? {
        let cache = try loadLimitsCache(paths: paths)
        guard let entry = cache.accounts[account] else { return nil }
        let nowMs = Date().timeIntervalSince1970 * 1000
        let ageMs = nowMs - entry.fetchedAt
        if ageMs > ttlMs {
            return nil
        }
        return (snapshot: entry.snapshot, ageMs: ageMs)
    }

    private func setCachedLimits(account: String, snapshot: RateLimitSnapshot, provider: String, paths: PathContext) throws {
        var cache = try loadLimitsCache(paths: paths)
        cache.accounts[account] = LimitsCacheEntry(
            snapshot: snapshot,
            fetchedAt: Date().timeIntervalSince1970 * 1000,
            provider: provider
        )
        try saveLimitsCache(cache, paths: paths)
    }

    private func loadLimitsCache(paths: PathContext) throws -> LimitsCacheFile {
        guard let data = readFileIfExists(paths.limitsCachePath), !data.isEmpty else {
            return LimitsCacheFile(version: 1, accounts: [:])
        }
        if let decoded = try? decoder.decode(LimitsCacheFile.self, from: data), decoded.version == 1 {
            return decoded
        }
        return LimitsCacheFile(version: 1, accounts: [:])
    }

    private func saveLimitsCache(_ cache: LimitsCacheFile, paths: PathContext) throws {
        let data = try encoder.encode(cache)
        try writeFileAtomic(data: data + Data("\n".utf8), path: paths.limitsCachePath, mode: 0o600)
    }

    // MARK: - Utils

    private static func nowISO() -> String {
        nowFormatter.string(from: Date())
    }

    private func validatedAccountName(_ name: String) throws -> String {
        let account = normalizeAccountName(name)
        guard isValidAccountName(account) else {
            throw MultiCodexCLIError(message: "Invalid account name. Use letters, numbers, underscore, or dash.")
        }
        return account
    }

    private func normalizeAccountName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isValidAccountName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil
    }

    private func shellQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}

struct MultiCodexCLIError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
