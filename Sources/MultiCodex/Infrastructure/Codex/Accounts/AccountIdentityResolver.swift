import Foundation

struct ResolvedAccountIdentity: Equatable {
    let email: String?
    let plan: String?
    let accountId: String?
    let authMethod: AuthMethod

    enum AuthMethod: Equatable {
        case oauth
        case apiKey
    }
}

extension CodexAccountService {
    func inferDefaultWorkspaceEmail(fromAuthPath authPath: String) -> String? {
        guard let authPayload = try? loadAuthPayload(from: authPath) else {
            return nil
        }
        return inferDefaultWorkspaceEmail(fromAuthPayload: authPayload)
    }

    func inferDefaultWorkspaceEmail(fromAuthPayload authPayload: [String: Any]) -> String? {
        guard let rawEmail = resolveFromAuthPayload(authPayload)?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !rawEmail.isEmpty
        else {
            return nil
        }

        let email = sanitizeIdentitySegment(rawEmail, allowAtSymbol: true, allowDot: true)

        guard !email.isEmpty else {
            return nil
        }

        return email
    }

    func resolveFromAuthPayload(_ authPayload: [String: Any]) -> ResolvedAccountIdentity? {
        if let apiKey = authPayload["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return ResolvedAccountIdentity(email: nil, plan: "api-key", accountId: nil, authMethod: .apiKey)
        }

        guard let tokens = authPayload["tokens"] as? [String: Any] else {
            return nil
        }

        let idClaims = (tokens["id_token"] as? String).flatMap(parseJWT)
        let accessClaims = (tokens["access_token"] as? String).flatMap(parseJWT)
        let idProfile = idClaims?["https://api.openai.com/profile"] as? [String: Any]
        let accessProfile = accessClaims?["https://api.openai.com/profile"] as? [String: Any]
        let idAuth = idClaims?["https://api.openai.com/auth"] as? [String: Any]
        let accessAuth = accessClaims?["https://api.openai.com/auth"] as? [String: Any]

        let email = normalizedIdentityField(
            (idClaims?["email"] as? String)
                ?? (idProfile?["email"] as? String)
                ?? (accessClaims?["email"] as? String)
                ?? (accessProfile?["email"] as? String)
        )
        let plan = normalizedIdentityField(
            (idAuth?["chatgpt_plan_type"] as? String)
                ?? (accessAuth?["chatgpt_plan_type"] as? String)
                ?? (idClaims?["chatgpt_plan_type"] as? String)
                ?? (accessClaims?["chatgpt_plan_type"] as? String)
        )
        let accountId = normalizedIdentityField(
            (tokens["account_id"] as? String)
                ?? (idAuth?["chatgpt_account_id"] as? String)
                ?? (accessAuth?["chatgpt_account_id"] as? String)
                ?? (idClaims?["chatgpt_account_id"] as? String)
                ?? (accessClaims?["chatgpt_account_id"] as? String)
        )

        guard email != nil || plan != nil || accountId != nil else {
            return nil
        }

        MultiCodexLog.log(
            .identity,
            level: .debug,
            "Resolved account identity from auth payload",
            metadata: [
                "hasEmail": email == nil ? "no" : "yes",
                "hasAccountId": accountId == nil ? "no" : "yes",
                "plan": plan ?? "none",
            ]
        )
        return ResolvedAccountIdentity(email: email, plan: plan, accountId: accountId, authMethod: .oauth)
    }

    func parseJWT(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else {
            return nil
        }

        var payloadSegment = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !payloadSegment.count.isMultiple(of: 4) {
            payloadSegment.append("=")
        }

        guard let payloadData = Data(base64Encoded: payloadSegment),
              let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private func normalizedIdentityField(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else {
            return nil
        }

        let payloadSegment = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - payloadSegment.count % 4) % 4
        let padded = payloadSegment + String(repeating: "=", count: paddingCount)

        guard let payloadData = Data(base64Encoded: padded),
              let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    private func resolveEmail(idClaims: [String: Any]?, accessClaims: [String: Any]?) -> String? {
        if let email = idClaims?["email"] as? String, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return email
        }
        if let profile = accessClaims?["https://api.openai.com/profile"] as? [String: Any],
           let email = profile["email"] as? String,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return email
        }
        return nil
    }

    private func sanitizeIdentitySegment(
        _ rawValue: String,
        allowAtSymbol: Bool,
        allowDot: Bool
    ) -> String {
        let lowered = rawValue.lowercased()
        var buffer = ""
        buffer.reserveCapacity(lowered.count)

        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" {
                buffer.unicodeScalars.append(scalar)
                continue
            }
            if allowAtSymbol, scalar == "@" {
                buffer.unicodeScalars.append(scalar)
                continue
            }
            if allowDot, scalar == "." {
                buffer.unicodeScalars.append(scalar)
                continue
            }
            buffer.append("-")
        }

        let collapsedDashes = buffer.replacingOccurrences(
            of: "-{2,}",
            with: "-",
            options: .regularExpression
        )

        let trimmed = collapsedDashes.trimmingCharacters(in: CharacterSet(charactersIn: "-._@"))
        return trimmed
    }
}
