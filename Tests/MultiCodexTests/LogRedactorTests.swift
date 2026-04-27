import XCTest
@testable import MultiCodex

final class LogRedactorTests: XCTestCase {
    func testRedactsEmails() {
        XCTAssertEqual(
            LogRedactor.redact("logged in as dev@example.com"),
            "logged in as <email>"
        )
    }

    func testRedactsBearerTokens() {
        XCTAssertEqual(
            LogRedactor.redact("Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456"),
            "Authorization: Bearer <token>"
        )
    }

    func testRedactsOAuthTokenFields() {
        let text = "access_token: abcdefghijklmnopqrstuvwxyz123456 refresh_token=zyxwvutsrqponmlkjihgfedcba654321"
        XCTAssertEqual(
            LogRedactor.redact(text),
            "access_token: <token> refresh_token=<token>"
        )
    }

    func testDoesNotRedactShortNonTokenStrings() {
        // 8-char strings that are NOT after access_token/refresh_token/bearer should pass through
        XCTAssertEqual(
            LogRedactor.redact("refreshed: yes"),
            "refreshed: yes"
        )
    }
}
