import Foundation

/// Exports and imports all account data for backup/migration purposes.
enum AccountExportService {
    struct ExportPayload: Codable {
        let version: Int
        let exportedAt: String
        let appVersion: String
        let accounts: [ExportedAccount]
        let preferences: ExportedPreferences?
        let currentAccount: String?
    }

    struct ExportedAccount: Codable {
        let name: String
        let auth: Data
    }

    struct ExportedPreferences: Codable {
        let accountSwitchingStrategy: String?
        let menuDensity: String?
        let accountSortCriterion: String?
        let accountSortWindow: String?
        let accountSortDirection: String?
        let limitsCacheTTLSeconds: Int?
    }

    struct ImportResult: Equatable {
        let imported: Int
        let skipped: Int
        let failed: Int
        let conflicts: [String]
    }

    struct AuthFilesExportResult: Equatable {
        let exported: Int
        let skippedAccounts: [String]
    }

    enum ImportMergeStrategy {
        case skipExisting
        case overwrite
    }

    enum ExportError: LocalizedError {
        case unsupportedVersion(Int)
        case noAccounts
        case invalidAccountName(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "Unsupported export file version: \(v)"
            case .noAccounts:
                return "No accounts to export."
            case .invalidAccountName(let name):
                return "Invalid account name in backup: \(name)"
            }
        }
    }

    // MARK: - Export

    static func exportData(
        accountService: CodexAccountService,
        preferencesStore: AppPreferencesStore
    ) throws -> Data {
        let paths = accountService.currentPaths()
        let config = try accountService.loadConfig(paths: paths)

        guard !config.accounts.isEmpty else {
            throw ExportError.noAccounts
        }

        var exportedAccounts: [ExportedAccount] = []
        for accountName in config.accounts {
            let authPath = accountService.managedAuthPath(for: accountName, paths: paths) ?? paths.accountAuthPath(accountName)
            guard let authData = try? Data(contentsOf: URL(fileURLWithPath: authPath)) else {
                MultiCodexLog.log(.config, level: .debug, "Skipping account \(accountName) — auth data missing")
                continue
            }
            exportedAccounts.append(ExportedAccount(name: accountName, auth: authData))
        }

        let payload = ExportPayload(
            version: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: "0.5.0",
            accounts: exportedAccounts,
            preferences: ExportedPreferences(
                accountSwitchingStrategy: preferencesStore.accountSwitchingStrategy.rawValue,
                menuDensity: preferencesStore.menuDensity.rawValue,
                accountSortCriterion: preferencesStore.accountSortCriterion.rawValue,
                accountSortWindow: preferencesStore.accountSortWindow.rawValue,
                accountSortDirection: preferencesStore.accountSortDirection.rawValue,
                limitsCacheTTLSeconds: preferencesStore.limitsCacheTTLSeconds
            ),
            currentAccount: config.currentAccount
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    static func exportAuthFiles(
        to directoryURL: URL,
        accountService: CodexAccountService
    ) throws -> AuthFilesExportResult {
        let paths = accountService.currentPaths()
        let config = try accountService.loadConfig(paths: paths)

        guard !config.accounts.isEmpty else {
            throw ExportError.noAccounts
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        var exported = 0
        var skippedAccounts: [String] = []
        for accountName in config.accounts {
            let authPath = accountService.managedAuthPath(for: accountName, paths: paths)
                ?? paths.accountAuthPath(accountName)
            guard let authData = try? Data(contentsOf: URL(fileURLWithPath: authPath)) else {
                skippedAccounts.append(accountName)
                MultiCodexLog.log(.config, level: .debug, "Skipping account \(accountName) — auth data missing")
                continue
            }

            let accountDirectoryURL = directoryURL.appendingPathComponent(accountName, isDirectory: true)
            try FileManager.default.createDirectory(at: accountDirectoryURL, withIntermediateDirectories: true)
            try writeAuthFileData(
                authData,
                to: accountDirectoryURL.appendingPathComponent("auth.json")
            )
            exported += 1
        }

        guard exported > 0 else {
            throw ExportError.noAccounts
        }

        return AuthFilesExportResult(exported: exported, skippedAccounts: skippedAccounts)
    }

    // MARK: - Import

    static func importAccounts(
        from url: URL,
        accountService: CodexAccountService,
        preferencesStore: inout AppPreferencesStore,
        mergeStrategy: ImportMergeStrategy = .skipExisting
    ) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let payload = try decoder.decode(ExportPayload.self, from: data)

        guard payload.version == 1 else {
            throw ExportError.unsupportedVersion(payload.version)
        }

        let paths = accountService.currentPaths()
        var imported = 0
        var skipped = 0
        let failed = 0
        var conflicts: [String] = []

        try accountService.withConfigMutationLock {
            var config = try accountService.loadConfig(paths: paths)

            for account in payload.accounts {
                let validatedName = try accountService.validatedAccountName(account.name)
                guard validatedName == account.name else {
                    throw ExportError.invalidAccountName(account.name)
                }
                let exists = config.accounts.contains(validatedName)

                if exists {
                    switch mergeStrategy {
                    case .skipExisting:
                        skipped += 1
                        conflicts.append(account.name)
                        continue
                    case .overwrite:
                        break
                    }
                }

                let dir = paths.accountDir(validatedName)
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let authPath = paths.accountAuthPath(validatedName)
                try account.auth.write(to: URL(fileURLWithPath: authPath), options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o600))],
                    ofItemAtPath: authPath
                )
                if let managedHome = accountService.managedHomeForMutatingAuth(account: validatedName, paths: paths) {
                    try ManagedCodexHomeFactory.writeAuthData(account.auth, to: managedHome)
                }

                if !exists {
                    config.accounts.insert(validatedName)
                    try accountService.saveConfig(config, paths: paths)
                }

                imported += 1
                MultiCodexLog.log(.config, level: .info, "Imported account \(account.name)")
            }
        }

        // Restore preferences
        if let prefs = payload.preferences {
            applyImportPreferences(prefs, to: &preferencesStore)
        }

        MultiCodexLog.log(
            .config,
            level: .info,
            "Import complete: \(imported) imported, \(skipped) skipped, \(failed) failed"
        )

        return ImportResult(imported: imported, skipped: skipped, failed: failed, conflicts: conflicts)
    }

    static func writeBackupData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    private static func writeAuthFileData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    private static func applyImportPreferences(_ prefs: ExportedPreferences, to store: inout AppPreferencesStore) {
        if let strategy = prefs.accountSwitchingStrategy,
           let value = AccountSwitchingStrategy(rawValue: strategy)
        {
            store.accountSwitchingStrategy = value
        }
        if let density = prefs.menuDensity,
           let value = MenuDensity(rawValue: density)
        {
            store.menuDensity = value
        }
        if let criterion = prefs.accountSortCriterion,
           let value = AccountSortCriterion(rawValue: criterion)
        {
            store.accountSortCriterion = value
        }
        if let window = prefs.accountSortWindow,
           let value = AccountSortWindow(rawValue: window)
        {
            store.accountSortWindow = value
        }
        if let direction = prefs.accountSortDirection,
           let value = SortDirection(rawValue: direction)
        {
            store.accountSortDirection = value
        }
        if let ttl = prefs.limitsCacheTTLSeconds {
            store.limitsCacheTTLSeconds = ttl
        }
    }
}
