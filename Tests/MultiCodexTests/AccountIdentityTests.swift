import XCTest
@testable import MultiCodex

final class AccountIdentityTests: XCTestCase {
    func testProviderAccountIDIsPrimaryIdentity() {
        let identity = AccountIdentityResolver.resolve(accountId: "acct_123", email: "dev@example.com")
        XCTAssertEqual(identity, .providerAccount(id: "acct_123"))
    }

    func testEmailOnlyFallsBackWhenNoAccountID() {
        let identity = AccountIdentityResolver.resolve(accountId: nil, email: "Dev@Example.COM")
        XCTAssertEqual(identity, .emailOnly(normalizedEmail: "dev@example.com"))
    }

    func testUnresolvedWhenBothMissing() {
        let identity = AccountIdentityResolver.resolve(accountId: nil, email: nil)
        XCTAssertEqual(identity, .unresolved)
    }

    func testMatchesProviderAccountIDs() {
        let a = AccountIdentity.providerAccount(id: "acct_123")
        let b = AccountIdentity.providerAccount(id: "acct_123")
        XCTAssertTrue(AccountIdentityMatcher.matches(a, b))
    }

    func testDoesNotMatchDifferentIDsWithSameEmail() {
        let a = AccountIdentity.providerAccount(id: "acct_123")
        let b = AccountIdentity.emailOnly(normalizedEmail: "dev@example.com")
        XCTAssertFalse(AccountIdentityMatcher.matches(a, b))
    }

    func testMatchesEmails() {
        let a = AccountIdentity.emailOnly(normalizedEmail: "dev@example.com")
        let b = AccountIdentity.emailOnly(normalizedEmail: "dev@example.com")
        XCTAssertTrue(AccountIdentityMatcher.matches(a, b))
    }
}
