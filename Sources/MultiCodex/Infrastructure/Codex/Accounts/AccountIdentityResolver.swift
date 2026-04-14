import Foundation

extension CodexAccountService {
    func inferDefaultWorkspaceEmail(fromAuthPath authPath: String) -> String? {
        guard let authPayload = try? loadAuthPayload(from: authPath) else {
            return nil
        }
        return inferDefaultWorkspaceEmail(fromAuthPayload: authPayload)
    }

    func inferDefaultWorkspaceEmail(fromAuthPayload authPayload: [String: Any]) -> String? {
        guard let tokens = authPayload["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              let claims = decodeJWTPayload(idToken)
        else {
            return nil
        }

        guard let rawEmail = (claims["email"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !rawEmail.isEmpty
        else {
            return nil
        }

        let workspaceRaw = defaultWorkspaceTitle(fromClaims: claims) ?? "workspace"
        let workspace = sanitizeIdentitySegment(workspaceRaw, allowAtSymbol: false, allowDot: false)
        let email = sanitizeIdentitySegment(rawEmail, allowAtSymbol: true, allowDot: true)

        guard !workspace.isEmpty, !email.isEmpty else {
            return nil
        }

        return "\(workspace)-\(email)"
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

    private func defaultWorkspaceTitle(fromClaims claims: [String: Any]) -> String? {
        guard let authInfo = claims["https://api.openai.com/auth"] as? [String: Any],
              let organizations = authInfo["organizations"] as? [Any]
        else {
            return nil
        }

        var fallbackTitle: String?
        for organization in organizations {
            guard let item = organization as? [String: Any] else {
                continue
            }

            if fallbackTitle == nil,
               let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty
            {
                fallbackTitle = title
            }

            if let isDefault = item["is_default"] as? Bool,
               isDefault,
               let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty
            {
                return title
            }
        }

        return fallbackTitle
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
