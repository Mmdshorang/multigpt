import Foundation
import XCTest
@testable import MultiCodex

final class JWTIdentityTests: XCTestCase {
    func testResolveFromAuthPayloadExtractsJWTIdentity() throws {
        let service = CodexAccountService()
        let token = makeJWT([
            "email": "DEV@Example.COM",
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": "plus",
                "chatgpt_account_id": "acct_123",
            ],
        ])

        let identity = try XCTUnwrap(service.resolveFromAuthPayload(["tokens": ["id_token": token]]))

        XCTAssertEqual(identity.email, "DEV@Example.COM")
        XCTAssertEqual(identity.plan, "plus")
        XCTAssertEqual(identity.accountId, "acct_123")
        XCTAssertEqual(identity.authMethod, .oauth)
    }

    func testResolveFromAuthPayloadRecognizesAPIKey() throws {
        let service = CodexAccountService()
        let identity = try XCTUnwrap(service.resolveFromAuthPayload(["OPENAI_API_KEY": "sk-test"]))

        XCTAssertEqual(identity.plan, "api-key")
        XCTAssertEqual(identity.authMethod, .apiKey)
    }

    func testParseJWTRejectsMalformedToken() {
        XCTAssertNil(CodexAccountService().parseJWT("not-a-jwt"))
    }

    private func makeJWT(_ payload: [String: Any]) -> String {
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [])
        return "\(header).\(base64URL(payloadData))."
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
