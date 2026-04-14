import Foundation

struct AccountsListPayload: Codable {
    let accounts: [AccountEntry]
    let currentAccount: String?
}

struct AccountEntry: Codable, Identifiable {
    let name: String
    let isCurrent: Bool
    let hasAuth: Bool
    let lastUsedAt: String?
    let lastLoginStatus: String?
    let defaultWorkspaceEmail: String?

    var id: String { name }

    init(
        name: String,
        isCurrent: Bool,
        hasAuth: Bool,
        lastUsedAt: String?,
        lastLoginStatus: String?,
        defaultWorkspaceEmail: String? = nil
    ) {
        self.name = name
        self.isCurrent = isCurrent
        self.hasAuth = hasAuth
        self.lastUsedAt = lastUsedAt
        self.lastLoginStatus = lastLoginStatus
        self.defaultWorkspaceEmail = defaultWorkspaceEmail
    }
}

struct LimitsPayload: Codable {
    let results: [LimitsResult]
    let errors: [LimitsErrorEntry]
}

struct LimitsResult: Codable {
    let account: String
    let source: String
    let snapshot: RateLimitSnapshot?
    let ageSec: Int?
}

struct LimitsErrorEntry: Codable {
    let account: String
    let message: String
}

struct RateLimitSnapshot: Codable {
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let credits: CreditsSnapshot?
}

struct RateLimitWindow: Codable, Equatable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Double?
}

struct CreditsSnapshot: Codable {
    let hasCredits: Bool?
    let unlimited: Bool?
    let balance: String?
}

struct SwitchAccountPayload: Codable {
    let currentAccount: String
}

struct AddAccountPayload: Codable {
    let account: String
    let currentAccount: String?
}

struct RemoveAccountPayload: Codable {
    let removedAccount: String
    let currentAccount: String?
}

struct RenameAccountPayload: Codable {
    let from: String
    let to: String
    let currentAccount: String?
}

struct ImportAccountPayload: Codable {
    let account: String
}

struct AccountStatusPayload: Codable {
    let account: String
    let exitCode: Int
    let stdout: String
    let stderr: String
    let output: String
    let checkedAt: String
}
