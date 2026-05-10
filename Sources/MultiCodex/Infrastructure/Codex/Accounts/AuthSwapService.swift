import Darwin
import Foundation

/// Handles account switching with atomic auth file operations.
enum AuthSwapService {
    struct SwapResult {
        let targetAccount: String
        let previousAccountPreserved: Bool
    }

    /// Switch the system codex auth to a target managed account's auth.
    static func switchToAccount(
        named targetName: String,
        previousAccountName: String?,
        paths: CodexAccountService.PathContext,
        force: Bool = false
    ) throws {
        let systemAuthURL = URL(fileURLWithPath: paths.defaultCodexAuthPath)

        // Step 1: Displaced account preservation — only write system auth back to
        // the previous account if it actually belongs to that account.
        if let previousName = previousAccountName,
           let currentSystemAuth = try? Data(contentsOf: URL(fileURLWithPath: paths.defaultCodexAuthPath))
        {
            let previousAccountAuth = try? readAuthData(account: previousName, paths: paths)

            if !force {
                if let previousAccountAuth,
                   !authDataMatches(currentSystemAuth, previousAccountAuth)
                {
                    let systemIdentity = resolveIdentity(from: currentSystemAuth)
                    let previousIdentity = resolveIdentity(from: previousAccountAuth)
                    throw AuthSwapError.externalAuthDetected(
                        previousAccount: previousName,
                        previousIdentity: previousIdentity,
                        systemIdentity: systemIdentity
                    )
                }
            }

            // Even in the force path, verify that system auth actually belongs to
            // the previous account before writing it back. This prevents account
            // data corruption when the system auth was modified externally.
            let shouldPreserve: Bool
            if let previousAccountAuth {
                shouldPreserve = identityBelongsToAccount(
                    systemAuth: currentSystemAuth,
                    storedAuth: previousAccountAuth
                )
            } else {
                // No stored auth for the previous account — safe to write (first-time setup).
                shouldPreserve = true
            }

            if shouldPreserve {
                try writeAuthData(currentSystemAuth, account: previousName, paths: paths)
                MultiCodexLog.log(
                    .auth,
                    level: .info,
                    "Preserved displaced auth to \(previousName)'s account storage"
                )
            } else {
                let systemIdentity = resolveIdentity(from: currentSystemAuth)
                let previousIdentity = previousAccountAuth.flatMap { resolveIdentity(from: $0) }
                MultiCodexLog.log(
                    .auth,
                    level: .error,
                    "Skipped displaced auth preservation: system auth identity does not match \(previousName)",
                    metadata: [
                        "systemEmail": systemIdentity?.email ?? "nil",
                        "systemAccountId": systemIdentity?.accountId ?? "nil",
                        "previousEmail": previousIdentity?.email ?? "nil",
                        "previousAccountId": previousIdentity?.accountId ?? "nil",
                    ]
                )
            }
        }

        // Step 2: Read target account's auth, preferring scoped managed homes.
        let targetAuthData = try readAuthData(account: targetName, paths: paths)

        guard let targetAuthData else {
            throw AuthSwapError.authNotFound(targetName)
        }

        // Step 3: Atomic swap using POSIX rename()
        let codexDir = URL(fileURLWithPath: paths.defaultCodexHome)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let stagedURL = codexDir.appendingPathComponent(
            "auth.json.multicodex-staged-\(UUID().uuidString)"
        )

        do {
            try targetAuthData.write(to: stagedURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: stagedURL.path
            )

            try atomicRename(at: stagedURL, to: systemAuthURL)

            MultiCodexLog.log(.auth, level: .info, "Switched system auth to \(targetName)")
        } catch {
            try? FileManager.default.removeItem(at: stagedURL)
            throw error
        }
    }

    private static func authDataMatches(_ lhs: Data, _ rhs: Data) -> Bool {
        guard let leftPayload = try? JSONSerialization.jsonObject(with: lhs) as? [String: Any],
              let rightPayload = try? JSONSerialization.jsonObject(with: rhs) as? [String: Any]
        else {
            return lhs == rhs
        }

        // Check API key identity
        let leftAPIKey = leftPayload["OPENAI_API_KEY"] as? String
        let rightAPIKey = rightPayload["OPENAI_API_KEY"] as? String
        if let leftAPIKey, let rightAPIKey {
            return leftAPIKey == rightAPIKey
        }
        if (leftAPIKey != nil) != (rightAPIKey != nil) {
            return false // Different auth methods
        }

        let leftTokens = leftPayload["tokens"] as? [String: Any]
        let rightTokens = rightPayload["tokens"] as? [String: Any]

        // Check account_id first
        let leftID = leftTokens?["account_id"] as? String
        let rightID = rightTokens?["account_id"] as? String
        if let leftID, let rightID {
            // Also check email if available to differentiate users in the same org
            let leftEmail = parseJWTEmail(leftTokens?["access_token"] as? String ?? "")
            let rightEmail = parseJWTEmail(rightTokens?["access_token"] as? String ?? "")
            if let leftEmail, let rightEmail {
                return leftID == rightID && leftEmail.lowercased() == rightEmail.lowercased()
            }
            return leftID == rightID
        }

        // Fallback: check email alone
        let leftEmail = parseJWTEmail(leftTokens?["access_token"] as? String ?? "")
        let rightEmail = parseJWTEmail(rightTokens?["access_token"] as? String ?? "")
        if let leftEmail, let rightEmail {
            return leftEmail.lowercased() == rightEmail.lowercased()
        }

        return lhs == rhs
    }

    /// Determines whether system auth data belongs to the same identity as stored account auth.
    /// More permissive than `authDataMatches` — returns true if identities overlap or if we can't determine.
    private static func identityBelongsToAccount(systemAuth: Data, storedAuth: Data) -> Bool {
        let systemIdentity = resolveIdentity(from: systemAuth)
        let storedIdentity = resolveIdentity(from: storedAuth)

        // If we can't resolve either identity, fall back to byte comparison
        guard let systemIdentity, let storedIdentity else {
            return systemAuth == storedAuth
        }

        // Different auth methods means definitely different accounts
        if systemIdentity.authMethod != storedIdentity.authMethod {
            return false
        }

        // Check email match (most reliable identifier)
        if let sysEmail = systemIdentity.email, let storedEmail = storedIdentity.email {
            return sysEmail.lowercased() == storedEmail.lowercased()
        }

        // Check account_id match
        if let sysId = systemIdentity.accountId, let storedId = storedIdentity.accountId {
            return sysId == storedId
        }

        // Cannot determine — be conservative, don't overwrite
        return false
    }

    private static func resolveIdentity(from data: Data) -> ResolvedAccountIdentity? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let apiKey = payload["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return ResolvedAccountIdentity(email: nil, plan: "api-key", accountId: nil, authMethod: .apiKey)
        }
        guard let tokens = payload["tokens"] as? [String: Any] else { return nil }
        let accountId = (tokens["account_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessToken = tokens["access_token"] as? String
        let email = accessToken.flatMap { parseJWTEmail($0) }
        guard email != nil || accountId != nil else { return nil }
        return ResolvedAccountIdentity(email: email, plan: nil, accountId: accountId, authMethod: .oauth)
    }

    private static func parseJWTEmail(_ token: String) -> String? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !payload.count.isMultiple(of: 4) { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (json["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ((json["https://api.openai.com/profile"] as? [String: Any])?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func readAuthData(account: String, paths: CodexAccountService.PathContext) throws -> Data? {
        if isManagedHomeMigrationComplete(paths: paths),
           let home = ManagedCodexHomeFactory.homeURL(for: account, multicodexHome: paths.multicodexHome),
           let data = try ManagedCodexHomeFactory.readAuthData(from: home)
        {
            return data
        }

        return try? Data(contentsOf: URL(fileURLWithPath: paths.accountAuthPath(account)))
    }

    private static func writeAuthData(_ data: Data, account: String, paths: CodexAccountService.PathContext) throws {
        let legacyURL = URL(fileURLWithPath: paths.accountAuthPath(account))
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: legacyURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: legacyURL.path
        )

        if isManagedHomeMigrationComplete(paths: paths) {
            let home = try ManagedCodexHomeFactory.createHome(for: account, multicodexHome: paths.multicodexHome)
            try ManagedCodexHomeFactory.writeAuthData(data, to: home)
        }
    }

    private static func isManagedHomeMigrationComplete(paths: CodexAccountService.PathContext) -> Bool {
        let markerURL = URL(fileURLWithPath: paths.multicodexHome)
            .appendingPathComponent(".managed-migration-complete")
        return FileManager.default.fileExists(atPath: markerURL.path)
    }

    private static func atomicRename(at sourceURL: URL, to destinationURL: URL) throws {
        let sourcePath = sourceURL.path
        let destinationPath = destinationURL.path

        let result = sourcePath.withCString { sourceFS in
            destinationPath.withCString { destFS in
                rename(sourceFS, destFS)
            }
        }

        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: destinationPath]
            )
        }
    }

    static func clearSystemAuth(paths: CodexAccountService.PathContext) throws {
        let systemAuthURL = URL(fileURLWithPath: paths.defaultCodexAuthPath)
        do {
            try FileManager.default.removeItem(at: systemAuthURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // Already absent is fine.
        }
        MultiCodexLog.log(.auth, level: .info, "Cleared system auth")
    }

    enum AuthSwapError: LocalizedError {
        case managedHomeNotFound(String)
        case authNotFound(String)
        case externalAuthDetected(
            previousAccount: String,
            previousIdentity: ResolvedAccountIdentity?,
            systemIdentity: ResolvedAccountIdentity?
        )

        var errorDescription: String? {
            switch self {
            case .managedHomeNotFound(let name):
                return "Managed home directory not found for account: \(name)"
            case .authNotFound(let name):
                return "Auth data not found for account: \(name)"
            case .externalAuthDetected(let previousAccount, _, let systemIdentity):
                let detected = systemIdentity?.email ?? systemIdentity?.accountId ?? "unknown account"
                return "Switch blocked: system auth is for \(detected), not \(previousAccount). Import the external account or force-switch."
            }
        }
    }
}
