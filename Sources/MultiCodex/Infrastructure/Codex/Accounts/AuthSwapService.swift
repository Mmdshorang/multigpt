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
                guard let previousAccountAuth else {
                    let systemIdentity = resolveIdentity(from: currentSystemAuth)
                    throw AuthSwapError.externalAuthDetected(
                        previousAccount: previousName,
                        previousIdentity: nil,
                        systemIdentity: systemIdentity
                    )
                }

                if !authDataMatches(currentSystemAuth, previousAccountAuth) {
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
                shouldPreserve = false
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
        identityBelongsToAccount(systemAuth: lhs, storedAuth: rhs)
    }

    /// Determines whether system auth data belongs to the same identity as stored account auth.
    /// Conservative by design: unknown or partial identity does not overwrite stored auth.
    private static func identityBelongsToAccount(systemAuth: Data, storedAuth: Data) -> Bool {
        if systemAuth == storedAuth {
            return true
        }

        let systemIdentity = resolveIdentity(from: systemAuth)
        let storedIdentity = resolveIdentity(from: storedAuth)

        // If either identity is unresolved, do not overwrite stored auth.
        guard let systemIdentity, let storedIdentity else {
            return false
        }

        // Different auth methods means definitely different accounts
        if systemIdentity.authMethod != storedIdentity.authMethod {
            return false
        }

        if systemIdentity.authMethod == .apiKey {
            return apiKey(from: systemAuth) == apiKey(from: storedAuth)
        }

        // Provider account ID is the strongest identity. A mismatch must not be
        // papered over by a shared email address.
        if systemIdentity.accountId != nil || storedIdentity.accountId != nil {
            guard let sysId = systemIdentity.accountId,
                  let storedId = storedIdentity.accountId
            else {
                return false
            }
            return sysId == storedId
        }

        if let sysEmail = systemIdentity.email, let storedEmail = storedIdentity.email {
            return sysEmail.lowercased() == storedEmail.lowercased()
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

        let idClaims = parseJWTClaims(tokens["id_token"] as? String)
        let accessClaims = parseJWTClaims(tokens["access_token"] as? String)
        let idProfile = idClaims?["https://api.openai.com/profile"] as? [String: Any]
        let accessProfile = accessClaims?["https://api.openai.com/profile"] as? [String: Any]
        let idAuth = idClaims?["https://api.openai.com/auth"] as? [String: Any]
        let accessAuth = accessClaims?["https://api.openai.com/auth"] as? [String: Any]

        let accountId = normalizedIdentityField(
            tokens["account_id"] as? String
                ?? idAuth?["chatgpt_account_id"] as? String
                ?? accessAuth?["chatgpt_account_id"] as? String
                ?? idClaims?["chatgpt_account_id"] as? String
                ?? accessClaims?["chatgpt_account_id"] as? String
        )
        let email = normalizedIdentityField(
            idClaims?["email"] as? String
                ?? idProfile?["email"] as? String
                ?? accessClaims?["email"] as? String
                ?? accessProfile?["email"] as? String
        )
        guard email != nil || accountId != nil else { return nil }
        return ResolvedAccountIdentity(email: email, plan: nil, accountId: accountId, authMethod: .oauth)
    }

    private static func apiKey(from data: Data) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return normalizedIdentityField(payload["OPENAI_API_KEY"] as? String)
    }

    private static func parseJWTClaims(_ token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !payload.count.isMultiple(of: 4) { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func normalizedIdentityField(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
