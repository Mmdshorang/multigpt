import Foundation

extension CodexAccountService {
    // MARK: - Usage API (primary limits path)

    func fetchRateLimitsViaApiForAuthPath(_ authPath: String) throws -> RateLimitSnapshot {
        var authPayload = try loadAuthPayload(from: authPath)

        if let apiKey = authPayload["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw CodexAccountServiceError(message: "Usage not available for API key.")
        }

        guard let tokens = asObject(authPayload["tokens"]),
              let rawAccessToken = tokens["access_token"] as? String
        else {
            throw CodexAccountServiceError(message: "Not logged in. Run `codex` to authenticate.")
        }

        var accessToken = rawAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw CodexAccountServiceError(message: "Not logged in. Run `codex` to authenticate.")
        }

        let accountID = (tokens["account_id"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAccountID = (accountID?.isEmpty == false) ? accountID : nil

        if shouldRefreshToken(authPayload),
           let refreshed = try refreshAccessToken(authPayload: &authPayload, authPath: authPath)
        {
            accessToken = refreshed
        }

        var usageResponse = try fetchUsage(accessToken: accessToken, accountID: normalizedAccountID)

        if usageResponse.statusCode == 401 || usageResponse.statusCode == 403 {
            if let refreshed = try refreshAccessToken(authPayload: &authPayload, authPath: authPath) {
                accessToken = refreshed
                usageResponse = try fetchUsage(accessToken: accessToken, accountID: normalizedAccountID)
            }
        }

        if usageResponse.statusCode == 401 || usageResponse.statusCode == 403 {
            throw CodexAccountServiceError(message: "Token expired. Run `codex` to log in again.")
        }

        guard (200...299).contains(usageResponse.statusCode) else {
            throw CodexAccountServiceError(message: "Usage request failed (HTTP \(usageResponse.statusCode)). Try again later.")
        }

        guard let usageBody = parseJSONRecord(usageResponse.data) else {
            throw CodexAccountServiceError(message: "Usage response invalid. Try again later.")
        }

        return parseUsageSnapshotFromWhamResponse(
            headers: usageResponse.headers,
            data: usageBody
        )
    }

    func fetchUsage(accessToken: String, accountID: String?) throws -> UsageHTTPResponse {
        let request = try UsageAPIClient.makeUsageRequest(
            urlString: Self.usageURLString,
            accessToken: accessToken,
            accountID: accountID
        )
        return try performHTTPRequest(request: request, timeoutSeconds: 10)
    }

    func refreshAccessToken(authPayload: inout [String: Any], authPath: String) throws -> String? {
        guard var tokens = asObject(authPayload["tokens"]),
              let refreshToken = tokens["refresh_token"] as? String,
              !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        guard let request = UsageAPIClient.makeRefreshTokenRequest(
            urlString: Self.refreshTokenURLString,
            body: buildRefreshRequestBody(refreshToken: refreshToken)
        ) else {
            return nil
        }

        let response: UsageHTTPResponse
        do {
            response = try performHTTPRequest(request: request, timeoutSeconds: 15)
        } catch {
            return nil
        }

        let responseBody = parseJSONRecord(response.data)
        if response.statusCode == 400 || response.statusCode == 401 {
            let code = refreshErrorCode(from: responseBody)
            throw CodexAccountServiceError(message: tokenErrorMessage(forRefreshCode: code))
        }

        guard (200...299).contains(response.statusCode) else {
            return nil
        }
        guard let responseBody,
              let nextAccessToken = responseBody["access_token"] as? String,
              !nextAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        tokens["access_token"] = nextAccessToken
        if let nextRefreshToken = responseBody["refresh_token"] as? String,
           !nextRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            tokens["refresh_token"] = nextRefreshToken
        }
        if let nextIDToken = responseBody["id_token"] as? String,
           !nextIDToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            tokens["id_token"] = nextIDToken
        }

        authPayload["tokens"] = tokens
        authPayload["last_refresh"] = Self.nowISO()
        try? persistAuthPayload(authPayload, path: authPath)
        return nextAccessToken
    }

    func performHTTPRequest(request: URLRequest, timeoutSeconds: TimeInterval) throws -> UsageHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: configuration)

        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var responseObject: HTTPURLResponse?
        var responseError: Error?

        let task = session.dataTask(with: request) { data, response, error in
            if let data {
                responseData = data
            }
            responseObject = response as? HTTPURLResponse
            responseError = error
            semaphore.signal()
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds + 1)
        session.finishTasksAndInvalidate()

        if waitResult == .timedOut {
            task.cancel()
            throw CodexAccountServiceError(message: "Usage request timed out. Try again later.")
        }
        if let responseError {
            throw CodexAccountServiceError(message: "Usage request failed: \(responseError.localizedDescription)")
        }
        guard let responseObject else {
            throw CodexAccountServiceError(message: "Usage response invalid. Try again later.")
        }

        return UsageHTTPResponse(
            statusCode: responseObject.statusCode,
            headers: responseObject.allHeaderFields,
            data: responseData
        )
    }

    func loadAuthPayload(from path: String) throws -> [String: Any] {
        guard let rawData = readFileIfExists(path), !rawData.isEmpty else {
            throw CodexAccountServiceError(message: "Not logged in. Run `codex` to authenticate.")
        }

        if let parsed = parseJSONRecord(rawData) {
            return parsed
        }

        if let rawText = String(data: rawData, encoding: .utf8),
           let decodedHexText = decodeHexUTF8(rawText),
           let decoded = parseJSONRecord(Data(decodedHexText.utf8))
        {
            return decoded
        }

        throw CodexAccountServiceError(message: "Not logged in. Run `codex` to authenticate.")
    }

    func persistAuthPayload(_ payload: [String: Any], path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try writeFileAtomic(data: data + Data("\n".utf8), path: path, mode: 0o600)
    }

    func parseUsageSnapshotFromWhamResponse(
        headers: [AnyHashable: Any],
        data: [String: Any]
    ) -> RateLimitSnapshot {
        let nowSec = Int(Date().timeIntervalSince1970)
        let rateLimit = asObject(data["rate_limit"])
        let primaryWindow = asObject(rateLimit?["primary_window"])
        let secondaryWindow = asObject(rateLimit?["secondary_window"])
        let reviewWindow = asObject(asObject(data["code_review_rate_limit"])?["primary_window"])

        let primaryHeaderUsedPercent = readHeaderNumber(headers: headers, name: "x-codex-primary-used-percent")
        let secondaryHeaderUsedPercent = readHeaderNumber(headers: headers, name: "x-codex-secondary-used-percent")

        let primary = buildWindow(
            usedPercent: primaryHeaderUsedPercent ?? readNumber(primaryWindow?["used_percent"]),
            windowDurationMins: readDurationMins(window: primaryWindow, fallbackMins: 300),
            resetsAt: readResetsAt(window: primaryWindow, nowSec: nowSec)
        )

        let secondaryCandidate = secondaryWindow ?? reviewWindow
        let secondary = buildWindow(
            usedPercent: secondaryHeaderUsedPercent
                ?? readNumber(secondaryWindow?["used_percent"])
                ?? readNumber(reviewWindow?["used_percent"]),
            windowDurationMins: readDurationMins(window: secondaryCandidate, fallbackMins: 10_080),
            resetsAt: readResetsAt(window: secondaryCandidate, nowSec: nowSec)
        )

        let bodyCredits = asObject(data["credits"])
        let creditsFromHeader = readHeaderNumber(headers: headers, name: "x-codex-credits-balance")
        let creditsFromBody = readNumber(bodyCredits?["balance"])
        let hasCredits = readBoolean(bodyCredits?["has_credits"])
        let unlimited = readBoolean(bodyCredits?["unlimited"])

        let credits: CreditsSnapshot?
        if creditsFromHeader != nil || creditsFromBody != nil || hasCredits != nil || unlimited != nil {
            let balance = creditsFromHeader.map(numberString) ?? creditsFromBody.map(numberString)
            credits = CreditsSnapshot(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
        } else {
            credits = nil
        }

        return RateLimitSnapshot(primary: primary, secondary: secondary, credits: credits)
    }

    func shouldRefreshToken(_ authPayload: [String: Any]) -> Bool {
        guard let raw = authPayload["last_refresh"] as? String,
              let parsed = parseISODate(raw)
        else {
            return true
        }
        return Date().timeIntervalSince(parsed) > Double(Self.refreshAgeSeconds)
    }

    func parseISODate(_ raw: String) -> Date? {
        if let parsed = Self.nowFormatter.date(from: raw) {
            return parsed
        }
        return Self.plainISOFormatter.date(from: raw)
    }

    func refreshErrorCode(from body: [String: Any]?) -> String? {
        if let errorObject = asObject(body?["error"]),
           let code = errorObject["code"] as? String
        {
            return code
        }
        if let error = body?["error"] as? String {
            return error
        }
        if let code = body?["code"] as? String {
            return code
        }
        return nil
    }

    func tokenErrorMessage(forRefreshCode code: String?) -> String {
        switch code {
        case "refresh_token_expired":
            return "Session expired. Run `codex` to log in again."
        case "refresh_token_reused":
            return "Token conflict. Run `codex` to log in again."
        case "refresh_token_invalidated":
            return "Token revoked. Run `codex` to log in again."
        default:
            return "Token expired. Run `codex` to log in again."
        }
    }

    func buildRefreshRequestBody(refreshToken: String) -> Data {
        let body = [
            "grant_type=refresh_token",
            "client_id=\(formURLEncode(Self.refreshClientID))",
            "refresh_token=\(formURLEncode(refreshToken))",
        ].joined(separator: "&")
        return Data(body.utf8)
    }

    func formURLEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func parseJSONRecord(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let record = object as? [String: Any]
        else {
            return nil
        }
        return record
    }

    func decodeHexUTF8(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned: String
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            cleaned = String(trimmed.dropFirst(2))
        } else {
            cleaned = trimmed
        }

        guard !cleaned.isEmpty,
              cleaned.count.isMultiple(of: 2),
              cleaned.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil
        else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            let pair = cleaned[index..<next]
            guard let value = UInt8(pair, radix: 16) else {
                return nil
            }
            bytes.append(value)
            index = next
        }

        return String(data: Data(bytes), encoding: .utf8)
    }

    func asObject(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    func readNumber(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func readBoolean(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID()
        {
            return number.boolValue
        }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    func readHeaderNumber(headers: [AnyHashable: Any], name: String) -> Double? {
        guard let value = readHeaderValue(headers: headers, name: name) else {
            return nil
        }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func readHeaderValue(headers: [AnyHashable: Any], name: String) -> String? {
        for (key, rawValue) in headers {
            let keyString = String(describing: key)
            if keyString.caseInsensitiveCompare(name) != .orderedSame {
                continue
            }
            if let stringValue = rawValue as? String {
                return stringValue
            }
            return String(describing: rawValue)
        }
        return nil
    }

    func readDurationMins(window: [String: Any]?, fallbackMins: Int) -> Int? {
        if let seconds = readNumber(window?["limit_window_seconds"]), seconds > 0 {
            return max(1, Int((seconds / 60.0).rounded()))
        }
        return fallbackMins
    }

    func readResetsAt(window: [String: Any]?, nowSec: Int) -> Double? {
        if let resetAt = readNumber(window?["reset_at"]) {
            return floor(resetAt)
        }
        if let resetAfter = readNumber(window?["reset_after_seconds"]) {
            return floor(Double(nowSec) + resetAfter)
        }
        return nil
    }

    func buildWindow(usedPercent: Double?, windowDurationMins: Int?, resetsAt: Double?) -> RateLimitWindow? {
        if usedPercent == nil, windowDurationMins == nil, resetsAt == nil {
            return nil
        }
        return RateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMins: windowDurationMins,
            resetsAt: resetsAt
        )
    }

    func numberString(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

}
