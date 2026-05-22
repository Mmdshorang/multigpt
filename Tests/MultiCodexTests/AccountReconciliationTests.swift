import XCTest
@testable import MultiCodex

final class AccountReconciliationTests: XCTestCase {
    func testDetectsExternalLoginToDifferentKnownAccountByEmail() {
        // Config says "Work" but system auth resolves to "Personal" via email
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: "Work",
            systemAuthLastModified: Date().addingTimeInterval(60),
            knownAccountLastModified: Date(),
            systemIdentity: ResolvedAccountIdentity(email: "me@example.com", plan: "plus", accountId: nil, authMethod: .oauth),
            accountIdentities: [
                "Work": .emailOnly(normalizedEmail: "dev@example.com"),
                "Personal": .emailOnly(normalizedEmail: "me@example.com"),
            ]
        )

        XCTAssertFalse(result.isInSync)
        XCTAssertEqual(result.detectedAccountName, "Personal")
        XCTAssertTrue(result.systemAuthChangedExternally)
    }

    func testDetectsExternalLoginByProviderAccountID() {
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: "Work",
            systemAuthLastModified: nil,
            knownAccountLastModified: nil,
            systemIdentity: ResolvedAccountIdentity(email: "dev@example.com", plan: "plus", accountId: "acct_personal", authMethod: .oauth),
            accountIdentities: [
                "Work": .providerAccount(id: "acct_work"),
                "Personal": .providerAccount(id: "acct_personal"),
            ]
        )

        XCTAssertFalse(result.isInSync)
        XCTAssertEqual(result.detectedAccountName, "Personal")
        // provider account ID takes precedence over email even if email matches Work
    }

    func testDetectsExternalLoginToUnknownAccount() {
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: "Work",
            systemAuthLastModified: Date().addingTimeInterval(60),
            knownAccountLastModified: Date(),
            systemIdentity: ResolvedAccountIdentity(email: "unknown@example.com", plan: "plus", accountId: nil, authMethod: .oauth),
            accountIdentities: ["Work": .emailOnly(normalizedEmail: "dev@example.com")]
        )

        XCTAssertFalse(result.isInSync)
        XCTAssertNil(result.detectedAccountName)
        XCTAssertEqual(result.detectedEmail, "unknown@example.com")
        XCTAssertTrue(result.systemAuthChangedExternally)
    }

    func testInSyncWhenSameAccountDetected() {
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: "Work",
            systemAuthLastModified: Date(),
            knownAccountLastModified: Date(),
            systemIdentity: ResolvedAccountIdentity(email: "dev@example.com", plan: "plus", accountId: nil, authMethod: .oauth),
            accountIdentities: ["Work": .emailOnly(normalizedEmail: "dev@example.com")]
        )

        XCTAssertTrue(result.isInSync)
        XCTAssertEqual(result.detectedAccountName, "Work")
    }

    func testOutOfSyncWithoutModificationTimestamp() {
        // Even without timestamps, identity mismatch should be detected
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: "Work",
            systemAuthLastModified: nil,
            knownAccountLastModified: nil,
            systemIdentity: ResolvedAccountIdentity(email: "other@example.com", plan: "plus", accountId: nil, authMethod: .oauth),
            accountIdentities: ["Work": .emailOnly(normalizedEmail: "dev@example.com")]
        )

        XCTAssertFalse(result.isInSync)
        XCTAssertFalse(result.systemAuthChangedExternally)
    }

    func testAmbiguousEmailIdentityDoesNotSelectArbitraryAccount() {
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: "Work",
            systemAuthLastModified: Date().addingTimeInterval(60),
            knownAccountLastModified: Date(),
            systemIdentity: ResolvedAccountIdentity(email: "dev@example.com", plan: "plus", accountId: nil, authMethod: .oauth),
            accountIdentities: [
                "Work": .emailOnly(normalizedEmail: "dev@example.com"),
                "Personal": .emailOnly(normalizedEmail: "dev@example.com"),
            ]
        )

        XCTAssertFalse(result.isInSync)
        XCTAssertNil(result.detectedAccountName)
        XCTAssertEqual(result.detectedEmail, "dev@example.com")
        XCTAssertTrue(result.systemAuthChangedExternally)
    }

    func testAmbiguousIdentityIsOutOfSyncEvenWithoutConfiguredCurrentAccount() {
        let result = AccountReconciliation.reconcile(
            configCurrentAccount: nil,
            systemAuthLastModified: Date().addingTimeInterval(60),
            knownAccountLastModified: nil,
            systemIdentity: ResolvedAccountIdentity(email: "dev@example.com", plan: "plus", accountId: nil, authMethod: .oauth),
            accountIdentities: [
                "Work": .emailOnly(normalizedEmail: "dev@example.com"),
                "Personal": .emailOnly(normalizedEmail: "dev@example.com"),
            ]
        )

        XCTAssertFalse(result.isInSync)
        XCTAssertNil(result.detectedAccountName)
        XCTAssertTrue(result.isAmbiguous)
    }
}
