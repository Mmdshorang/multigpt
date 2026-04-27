import Foundation

/// Creates and manages isolated CODEX_HOME directories for each account.
enum ManagedCodexHomeFactory {
    static let homesRootName = "homes"

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("MultiCodex", isDirectory: true)
        return base.appendingPathComponent(homesRootName, isDirectory: true)
    }

    static func createHome(for accountName: String, fileManager: FileManager = .default) throws -> URL {
        let sanitized = sanitize(accountName)
        let homeURL = defaultRootURL(fileManager: fileManager)
            .appendingPathComponent(sanitized, isDirectory: true)

        try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)

        let sessionsURL = homeURL.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)

        return homeURL
    }

    static func homeURL(for accountName: String, fileManager: FileManager = .default) -> URL? {
        let sanitized = sanitize(accountName)
        let homeURL = defaultRootURL(fileManager: fileManager)
            .appendingPathComponent(sanitized, isDirectory: true)
        return fileManager.fileExists(atPath: homeURL.path) ? homeURL : nil
    }

    static func scopedEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        managedHome: URL
    ) -> [String: String] {
        var env = base
        env["CODEX_HOME"] = managedHome.path
        return env
    }

    static func readAuthData(from homeURL: URL) throws -> Data? {
        let authURL = homeURL.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: authURL.path) else { return nil }
        return try Data(contentsOf: authURL)
    }

    static func writeAuthData(_ data: Data, to homeURL: URL) throws {
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let authURL = homeURL.appendingPathComponent("auth.json")
        try data.write(to: authURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: authURL.path
        )
    }

    static func validateSafeDeletion(_ url: URL, fileManager: FileManager = .default) throws {
        let rootPath = defaultRootURL(fileManager: fileManager).standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(rootPrefix), targetPath != rootPath else {
            throw ManagedHomeError.unsafeDeletion(url.path)
        }
    }

    static func sanitize(_ name: String) -> String {
        name.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined()
    }

    enum ManagedHomeError: LocalizedError {
        case unsafeDeletion(String)
        var errorDescription: String? {
            switch self {
            case .unsafeDeletion(let path):
                return "Refusing to delete directory outside managed root: \(path)"
            }
        }
    }
}
