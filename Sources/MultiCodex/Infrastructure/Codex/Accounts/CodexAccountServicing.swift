import Foundation

protocol CodexAccountServicing: AnyObject {
    var customCodexPath: String? { get set }
    var limitsCacheTTLSeconds: Int { get set }
    var resolutionHint: String? { get }

    func fetchAccounts() async throws -> AccountsListPayload
    func fetchLimits(refreshLive: Bool) async throws -> LimitsPayload
    func switchAccount(name: String) async throws
    func removeAccount(name: String, deleteData: Bool) async throws -> RemoveAccountPayload
    func renameAccount(from oldName: String, to newName: String) async throws -> RenameAccountPayload
    func importDefaultAuth(into name: String) async throws -> ImportAccountPayload
    func importAuth(fromHome homePath: String, into name: String) async throws -> ImportAccountPayload
    func fetchStatus(name: String) async throws -> AccountStatusPayload
    func fetchStatusForLoginHome(_ homePath: String, accountName: String) async throws -> AccountStatusPayload
    func openLoginInTerminal(account name: String, loginHome: String?) throws
    func openNewAccountLoginInTerminal(newAccountName name: String, loginHome: String?) throws
    func loginInApp(account name: String, createIfNeeded: Bool, loginHome: String?) async throws -> String
    func inferDefaultWorkspaceEmail(fromLoginHome homePath: String) -> String?
    func effectiveMulticodexHomePath() -> String
    func probeRuntime() -> RuntimeProbe
    func refreshStaleTokens() async -> [String: Error]
    func persistCurrentAccountIfKnown(_ name: String) throws
    func storedAuthModifiedDate(for account: String, paths: CodexAccountService.PathContext) -> Date?
    func resolveFromAuthPayload(_ authPayload: [String: Any]) -> ResolvedAccountIdentity?
    func resolvedIdentityForAccount(name: String) -> ResolvedAccountIdentity?
    func currentPaths(loginHome: String?) -> CodexAccountService.PathContext
}

extension CodexAccountService: CodexAccountServicing {}

extension CodexAccountServicing {
    func currentPaths() -> CodexAccountService.PathContext {
        currentPaths(loginHome: nil)
    }
}
