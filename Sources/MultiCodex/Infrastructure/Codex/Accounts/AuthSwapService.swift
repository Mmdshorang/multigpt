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
           let previousHome = ManagedCodexHomeFactory.homeURL(for: previousName),
           let currentSystemAuth = try? Data(contentsOf: URL(fileURLWithPath: paths.defaultCodexAuthPath))
        {
            let managedAuth = try? ManagedCodexHomeFactory.readAuthData(from: previousHome)
            if managedAuth == nil || managedAuth != currentSystemAuth {
                try? ManagedCodexHomeFactory.writeAuthData(currentSystemAuth, to: previousHome)
                MultiCodexLog.log(
                    .auth,
                    level: .info,
                    "Preserved displaced auth to \(previousName)'s managed home"
                )
            }
        }

        // Step 2: Read target account's auth
        guard let targetHome = ManagedCodexHomeFactory.homeURL(for: targetName) else {
            throw AuthSwapError.managedHomeNotFound(targetName)
        }
        guard let targetAuthData = try ManagedCodexHomeFactory.readAuthData(from: targetHome) else {
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
