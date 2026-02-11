import Foundation

struct CommandEnvelope<T: Decodable>: Decodable {
    let schemaVersion: Int?
    let command: String?
    let ok: Bool
    let data: T?
    let error: CommandErrorPayload?
}

struct CommandErrorPayload: Decodable {
    let message: String
    let code: String?
}

struct AccountsListPayload: Decodable {
    let accounts: [AccountEntry]
    let currentAccount: String?
}

struct AccountEntry: Decodable, Identifiable {
    let name: String
    let isCurrent: Bool
    let hasAuth: Bool
    let lastUsedAt: String?
    let lastLoginStatus: String?

    var id: String { name }
}

struct LimitsPayload: Decodable {
    let results: [LimitsResult]
    let errors: [LimitsErrorEntry]
}

struct LimitsResult: Decodable {
    let account: String
    let source: String
    let snapshot: RateLimitSnapshot?
    let ageSec: Int?
}

struct LimitsErrorEntry: Decodable {
    let account: String
    let message: String
}

struct RateLimitSnapshot: Decodable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
}

struct RateLimitWindow: Decodable, Equatable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
}

struct CreditsSnapshot: Decodable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?
}

struct SwitchAccountPayload: Decodable {
    let currentAccount: String
}

struct AddAccountPayload: Decodable {
    let account: String
    let currentAccount: String?
}

struct RemoveAccountPayload: Decodable {
    let removedAccount: String
    let currentAccount: String?
}

struct RenameAccountPayload: Decodable {
    let from: String
    let to: String
    let currentAccount: String?
}

struct ImportAccountPayload: Decodable {
    let account: String
}

struct AccountStatusPayload: Decodable {
    let account: String
    let exitCode: Int
    let stdout: String
    let stderr: String
    let output: String
    let checkedAt: String
}
