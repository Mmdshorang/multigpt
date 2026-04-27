import Foundation

/// Robust account identity model.
/// Identity hierarchy (most reliable → least):
/// 1. providerAccountID — unique per OpenAI account, survives email changes
/// 2. email — may be shared across workspace accounts (less reliable)
/// 3. unresolved — no identity information available
enum AccountIdentity: Equatable, Hashable, Sendable {
    case providerAccount(id: String)
    case emailOnly(normalizedEmail: String)
    case unresolved
}

/// Resolves identity from auth payload data.
enum AccountIdentityResolver {
    static func resolve(accountId: String?, email: String?) -> AccountIdentity {
        if let id = normalizeAccountId(accountId) {
            return .providerAccount(id: id)
        }
        if let email = normalizeEmail(email) {
            return .emailOnly(normalizedEmail: email)
        }
        return .unresolved
    }

    static func normalizeEmail(_ email: String?) -> String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else { return nil }
        return email.lowercased()
    }

    static func normalizeAccountId(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty
        else { return nil }
        return id
    }
}

/// Matches identities between stored and runtime accounts.
enum AccountIdentityMatcher {
    static func matches(_ a: AccountIdentity, _ b: AccountIdentity) -> Bool {
        switch (a, b) {
        case let (.providerAccount(idA), .providerAccount(idB)):
            return idA == idB
        case let (.emailOnly(emailA), .emailOnly(emailB)):
            return emailA == emailB
        case (.providerAccount, .emailOnly), (.emailOnly, .providerAccount):
            return false
        case (.unresolved, _), (_, .unresolved):
            return false
        }
    }
}
