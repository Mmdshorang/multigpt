import Foundation

enum UsageAPIClient {
    static func makeUsageRequest(
        urlString: String,
        accessToken: String,
        accountID: String?
    ) throws -> URLRequest {
        guard let url = URL(string: urlString) else {
            throw CodexAccountServiceError(message: "Usage request URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multicodex", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    static func makeRefreshTokenRequest(
        urlString: String,
        body: Data
    ) -> URLRequest? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
