import Darwin
import Foundation

final class CodexAccountService {
    static let defaultLimitsCacheTTLSeconds = 1_200
    static let minLimitsCacheTTLSeconds = 60
    static let maxLimitsCacheTTLSeconds = 7_200

    static let usageURLString = "https://chatgpt.com/backend-api/wham/usage"
    static let refreshTokenURLString = "https://auth.openai.com/oauth/token"
    static let refreshClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let refreshAgeSeconds = 8 * 24 * 60 * 60

    static let nowFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plainISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    typealias ProcessResult = CodexCommandResult
    typealias NativeConfig = AccountConfigRecord

    struct AccountMeta: Codable {
        var createdAt: String
        var lastUsedAt: String?
        var lastLoginStatus: String?
        var lastLoginCheckedAt: String?
        var updatedAt: String?
    }

    struct AuthLockOwner: Codable {
        let pid: Int32
        let startedAt: String
        let account: String
    }

    final class AuthLockHandle {
        private let lockDir: String
        private let fileManager = FileManager.default

        init(lockDir: String) {
            self.lockDir = lockDir
        }

        func release() {
            try? fileManager.removeItem(atPath: lockDir)
        }
    }

    struct LimitsCacheEntry: Codable {
        let snapshot: RateLimitSnapshot
        let fetchedAt: Double
        let provider: String?
    }

    typealias LimitsCacheFile = LimitsCacheRecord<LimitsCacheEntry>

    struct UsageHTTPResponse {
        let statusCode: Int
        let headers: [AnyHashable: Any]
        let data: Data
    }

    typealias CodexRuntime = CodexRuntimeDescriptor

    struct RuntimeProbe {
        let isAvailable: Bool
        let summary: String
    }

    enum ExistingAccountBehavior {
        case ignore
        case fail
    }

    struct PathContext {
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

    let fileManager = FileManager.default
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    // Kept for backward compatibility with existing settings key.
    // This now points to a codex executable path/name (not Node).
    var customCodexPath: String?
    var sandboxHomeDirectory: String?
    var sandboxMulticodexHomeDirectory: String?
    var limitsCacheTTLSeconds: Int = defaultLimitsCacheTTLSeconds

    var resolutionHint: String?

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        limitsCacheTTLSeconds = Self.normalizedLimitsCacheTTLSeconds(limitsCacheTTLSeconds)
    }

    static func normalizedLimitsCacheTTLSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minLimitsCacheTTLSeconds), maxLimitsCacheTTLSeconds)
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
        let command = try makeTerminalCodexLoginCommand(accountName: name, firstTime: false)
        try launchTerminal(script: command)
    }

    func openNewAccountLoginInTerminal(newAccountName name: String) throws {
        _ = try addAccountIfNeededNow(name: name)
        _ = try switchAccountNow(name: name)
        let command = try makeTerminalCodexLoginCommand(accountName: name, firstTime: true)
        try launchTerminal(script: command)
    }

    func loginInApp(account name: String, createIfNeeded: Bool) async throws -> String {
        if createIfNeeded {
            _ = try addAccountIfNeededNow(name: name)
        }
        _ = try switchAccountNow(name: name)

        let result = try await runCodexCaptureAsync(arguments: ["login"])
        let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            throw CodexAccountServiceError(message: combined.isEmpty ? "Login failed." : combined)
        }
        return combined
    }

    func effectiveMulticodexHomePath() -> String {
        currentPaths().multicodexHome
    }

    func probeRuntime() -> RuntimeProbe {
        do {
            let result = try runCodexCapture(arguments: ["--version"])
            let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            if result.exitCode == 0 {
                let summary = combined.isEmpty ? "codex runtime is available." : combined
                return RuntimeProbe(isAvailable: true, summary: summary)
            }
            let summary = combined.isEmpty ? "codex runtime check failed." : combined
            return RuntimeProbe(isAvailable: false, summary: summary)
        } catch {
            return RuntimeProbe(isAvailable: false, summary: error.localizedDescription)
        }
    }
}

struct CodexAccountServiceError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
