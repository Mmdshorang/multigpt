import Foundation

protocol CodexAccountServicing: AnyObject {
    var customCodexPath: String? { get set }
    var sandboxHomeDirectory: String? { get set }
    var sandboxMulticodexHomeDirectory: String? { get set }
    var limitsCacheTTLSeconds: Int { get set }
    var resolutionHint: String? { get }

    func fetchAccounts() async throws -> AccountsListPayload
    func fetchLimits(refreshLive: Bool) async throws -> LimitsPayload
    func switchAccount(name: String) async throws
    func removeAccount(name: String, deleteData: Bool) async throws -> RemoveAccountPayload
    func renameAccount(from oldName: String, to newName: String) async throws -> RenameAccountPayload
    func importDefaultAuth(into name: String) async throws -> ImportAccountPayload
    func fetchStatus(name: String) async throws -> AccountStatusPayload
    func openLoginInTerminal(account name: String) throws
    func openNewAccountLoginInTerminal(newAccountName name: String) throws
    func loginInApp(account name: String, createIfNeeded: Bool) async throws -> String
    func effectiveMulticodexHomePath() -> String
    func probeRuntime() -> CodexAccountService.RuntimeProbe
}

extension CodexAccountService: CodexAccountServicing {}
