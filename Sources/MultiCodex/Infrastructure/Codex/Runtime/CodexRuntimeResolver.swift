import Foundation

struct CodexRuntimeDescriptor {
    let executableURL: URL
    let prefixArguments: [String]
    let display: String
}

enum CodexRuntimeResolver {
    static func resolve(
        customCodexPath: String?,
        fileManager: FileManager,
        environment: [String: String]
    ) throws -> CodexRuntimeDescriptor {
        func runtimeForRaw(_ raw: String, source: String) throws -> CodexRuntimeDescriptor {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CodexAccountServiceError(message: "Empty runtime value for \(source).")
            }
            if trimmed.contains("/") {
                let expanded = (trimmed as NSString).expandingTildeInPath
                if fileManager.isExecutableFile(atPath: expanded) {
                    return CodexRuntimeDescriptor(
                        executableURL: URL(fileURLWithPath: expanded),
                        prefixArguments: [],
                        display: "\(expanded) [\(source)]"
                    )
                }
                throw CodexAccountServiceError(message: "Configured codex executable is not executable: \(expanded)")
            }
            return CodexRuntimeDescriptor(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                prefixArguments: [trimmed],
                display: "\(trimmed) (from PATH, \(source))"
            )
        }

        func runtimeForDetectedExecutable(_ path: String, source: String?) -> CodexRuntimeDescriptor {
            CodexRuntimeDescriptor(
                executableURL: URL(fileURLWithPath: path),
                prefixArguments: [],
                display: source.map { "\(path) (\($0))" } ?? path
            )
        }

        if let custom = customCodexPath?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let lower = custom.lowercased()
            if !lower.hasSuffix("/node") && lower != "node" {
                return try runtimeForRaw(custom, source: "custom")
            }
        }

        if let envRaw = environment["MULTICODEX_CODEX"], !envRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try runtimeForRaw(envRaw, source: "MULTICODEX_CODEX")
        }

        if let resolvedFromWhich = resolveCodexPathUsingWhich(environment: environment, fileManager: fileManager) {
            return runtimeForDetectedExecutable(resolvedFromWhich, source: "from which")
        }

        if let resolvedFromWhere = resolveCodexPathUsingWhere(environment: environment, fileManager: fileManager) {
            return runtimeForDetectedExecutable(resolvedFromWhere, source: "from where")
        }

        if let resolvedFromPathScan = resolveCodexPathFromPATH(environment: environment, fileManager: fileManager) {
            return runtimeForDetectedExecutable(resolvedFromPathScan, source: "from PATH scan")
        }

        let knownPaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ]

        for codexPath in knownPaths where fileManager.isExecutableFile(atPath: codexPath) {
            return runtimeForDetectedExecutable(codexPath, source: nil)
        }

        return CodexRuntimeDescriptor(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            prefixArguments: ["codex"],
            display: "codex (from PATH)"
        )
    }

    private static func resolveCodexPathUsingWhich(
        environment: [String: String],
        fileManager: FileManager
    ) -> String? {
        let output = ProcessOutputReader.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/which"),
            arguments: ["-a", "codex"],
            environment: ExecutableSearchPath.environment(from: environment)
        )
        return firstExecutablePath(in: output, fileManager: fileManager)
    }

    private static func resolveCodexPathUsingWhere(
        environment: [String: String],
        fileManager: FileManager
    ) -> String? {
        guard fileManager.isExecutableFile(atPath: "/bin/zsh") else {
            return nil
        }

        let output = ProcessOutputReader.run(
            executableURL: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "where codex"],
            environment: ExecutableSearchPath.environment(from: environment)
        )
        return firstExecutablePath(in: output, fileManager: fileManager)
    }

    private static func resolveCodexPathFromPATH(
        environment: [String: String],
        fileManager: FileManager
    ) -> String? {
        let pathValue = ExecutableSearchPath.environment(from: environment)["PATH"]
        for pathEntry in ExecutableSearchPath.components(from: pathValue) {
            let expandedEntry = (pathEntry as NSString).expandingTildeInPath
            let candidate = (expandedEntry as NSString).appendingPathComponent("codex")
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func firstExecutablePath(
        in output: String?,
        fileManager: FileManager
    ) -> String? {
        guard let output else {
            return nil
        }

        var seen = Set<String>()

        for token in output.split(whereSeparator: \.isWhitespace) {
            let candidate = (String(token) as NSString).expandingTildeInPath
            guard candidate.contains("/"), seen.insert(candidate).inserted else {
                continue
            }
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}
