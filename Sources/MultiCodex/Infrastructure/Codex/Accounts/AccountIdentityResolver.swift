import Foundation

extension CodexAccountService {
    func inferDefaultWorkspaceEmail(fromAuthPath authPath: String) -> String? {
        guard let authPayload = try? loadAuthPayload(from: authPath) else {
            return nil
        }
        return inferDefaultWorkspaceEmail(fromAuthPayload: authPayload)
    }

    func inferDefaultWorkspaceEmail(fromAuthPayload authPayload: [String: Any]) -> String? {
        guard let tokens = authPayload["tokens"] as? [String: Any]
        else {
            return nil
        }

        let idClaims = (tokens["id_token"] as? String).flatMap(decodeJWTPayload)
        let accessClaims = (tokens["access_token"] as? String).flatMap(decodeJWTPayload)

        guard let rawEmail = resolveEmail(idClaims: idClaims, accessClaims: accessClaims)?
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
