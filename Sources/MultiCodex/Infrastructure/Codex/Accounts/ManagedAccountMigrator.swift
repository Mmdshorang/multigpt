import Foundation

/// Migrates legacy accounts from ~/.config/multicodex/accounts/ to managed homes.
/// Runs once on first launch after upgrade. Non-destructive — keeps legacy data as backup.
enum ManagedAccountMigrator {
    static func migrateIfNeeded(paths: CodexAccountService.PathContext) throws -> Int {
        let markerURL = URL(fileURLWithPath: paths.multicodexHome)
            .appendingPathComponent(".managed-migration-complete")

        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return 0 }

        let legacyAccountsDir = paths.accountsDir
        guard FileManager.default.fileExists(atPath: legacyAccountsDir) else {
            try? Data().write(to: markerURL)
            return 0
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: legacyAccountsDir)
        var migrated = 0

        for accountName in contents {
            let legacyAuthPath = paths.accountAuthPath(accountName)
            guard FileManager.default.fileExists(atPath: legacyAuthPath) else { continue }

            let managedHome = try ManagedCodexHomeFactory.createHome(for: accountName, multicodexHome: paths.multicodexHome)
            let authData = try Data(contentsOf: URL(fileURLWithPath: legacyAuthPath))
            try ManagedCodexHomeFactory.writeAuthData(authData, to: managedHome)

            MultiCodexLog.log(
                .config,
                level: .info,
                "Migrated account \(accountName) to managed home at \(managedHome.path)"
            )
            migrated += 1
        }

        try? Data("migrated \(migrated) accounts at \(ISO8601DateFormatter().string(from: Date()))".utf8)
            .write(to: markerURL)

        MultiCodexLog.log(
            .config,
            level: .info,
            "Migration complete: \(migrated) accounts migrated to managed homes"
        )

        return migrated
    }
}
