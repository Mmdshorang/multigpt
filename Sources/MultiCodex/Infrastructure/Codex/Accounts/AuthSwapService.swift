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
        paths: CodexAccountService.PathContext
    ) throws {
        let systemAuthURL = URL(fileURLWithPath: paths.defaultCodexAuthPath)

        // Step 1: Displaced account preservation
        if let previousName = previousAccountName,
           let currentSystemAuth = try? Data(contentsOf: URL(fileURLWithPath: paths.defaultCodexAuthPath))
        {
            try? writeAuthData(currentSystemAuth, account: previousName, paths: paths)
            MultiCodexLog.log(
                .auth,
                level: .info,
                "Preserved displaced auth to \(previousName)'s account storage"
            )
        }

        // Step 2: Read target account's auth, preferring scoped managed homes.
        let targetAuthData = try readAuthData(account: targetName, paths: paths)

        guard let targetAuthData else {
            try? FileManager.default.removeItem(at: systemAuthURL)
            MultiCodexLog.log(.auth, level: .info, "Cleared system auth for \(targetName)")
            return
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

    enum AuthSwapError: LocalizedError {
        case managedHomeNotFound(String)
        case authNotFound(String)

        var errorDescription: String? {
            switch self {
            case .managedHomeNotFound(let name):
                return "Managed home directory not found for account: \(name)"
            case .authNotFound(let name):
                return "Auth data not found for account: \(name)"
            }
        }
    }
}
