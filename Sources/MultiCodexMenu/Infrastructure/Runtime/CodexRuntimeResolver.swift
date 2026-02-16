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

        if let custom = customCodexPath?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            // Migration guard: ignore legacy Node path values.
            let lower = custom.lowercased()
            if !lower.hasSuffix("/node") && lower != "node" {
                return try runtimeForRaw(custom, source: "custom")
            }
        }

        if let envRaw = environment["MULTICODEX_CODEX"], !envRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try runtimeForRaw(envRaw, source: "MULTICODEX_CODEX")
        }

        if let resolvedFromWhich = resolveCodexPathUsingWhich(environment: environment, fileManager: fileManager) {
            return CodexRuntimeDescriptor(
                executableURL: URL(fileURLWithPath: resolvedFromWhich),
                prefixArguments: [],
                display: "\(resolvedFromWhich) (from which)"
            )
        }

        let knownPaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ]

        for codexPath in knownPaths where fileManager.isExecutableFile(atPath: codexPath) {
            return CodexRuntimeDescriptor(
                executableURL: URL(fileURLWithPath: codexPath),
                prefixArguments: [],
                display: codexPath
            )
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]

        var commandEnvironment = environment
        if commandEnvironment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            commandEnvironment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        process.environment = commandEnvironment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let resolvedPath = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedPath.isEmpty, fileManager.isExecutableFile(atPath: resolvedPath) else {
            return nil
        }
        return resolvedPath
    }
}
