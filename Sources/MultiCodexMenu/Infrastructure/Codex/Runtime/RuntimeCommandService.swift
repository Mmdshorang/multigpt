import Foundation

// RuntimeCommandService
extension CodexAccountService {
    func launchTerminal(script: String) throws {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\"",
            "-e", "if not (exists front window) then",
            "-e", "do script \"\(escaped)\"",
            "-e", "else",
            "-e", "do script \"\(escaped)\" in front window",
            "-e", "end if",
            "-e", "activate",
            "-e", "end tell",
        ]

        do {
            try process.run()
        } catch {
            throw CodexAccountServiceError(message: "Could not open Terminal for login: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CodexAccountServiceError(message: "Could not launch Terminal login session (exit \(process.terminationStatus)).")
        }
    }

    func makeTerminalCodexLoginCommand(accountName: String, firstTime: Bool, loginHome: String? = nil) throws -> String {
        let appName = shellQuote("MultiCodex")
        let account = shellQuote(accountName)
        let codexLoginCommand = try makeCodexShellCommand(arguments: ["login"], loginHome: loginHome)

        var lines = terminalPreambleLines(loginHome: loginHome)
        if firstTime {
            lines.append("echo \"Starting first-time MultiCodex login...\"")
            lines.append("echo \"Account \(account) is ready and can be renamed later in Settings.\"")
        } else {
            lines.append("echo \"Starting MultiCodex login flow for \(account)...\"")
        }
        lines.append(codexLoginCommand)
        lines.append("LOGIN_EXIT=$?")
        lines.append("if [ \"$LOGIN_EXIT\" -eq 0 ]; then")
        lines.append("  echo \"Login completed.\"")
        lines.append("else")
        lines.append("  echo \"Login failed (exit $LOGIN_EXIT).\"")
        lines.append("fi")
        lines.append("open -a \(appName) >/dev/null 2>&1 || true")
        lines.append("exit $LOGIN_EXIT")

        return lines.joined(separator: "\n")
    }

    // MARK: - Runtime and process

    func resolveCodexRuntime() throws -> CodexRuntime {
        try resolveCodexRuntime(environment: baseEnvironment())
    }

    private func resolveCodexRuntime(environment: [String: String]) throws -> CodexRuntime {
        let runtime = try CodexRuntimeResolver.resolve(
            customCodexPath: customCodexPath,
            fileManager: fileManager,
            environment: environment
        )
        updateResolutionHint(runtime: runtime)
        return runtime
    }

    func updateResolutionHint(runtime: CodexRuntime) {
        var hint = "Codex runtime: \(runtime.display)"
        let paths = currentPaths()
        hint += " | HOME: \(paths.homeDir)"
        hint += " | MULTICODEX_HOME: \(paths.multicodexHome)"
        resolutionHint = hint
    }

    func runCodexCapture(arguments: [String], loginHome: String? = nil) throws -> ProcessResult {
        let context = try resolvedRuntimeContext(loginHome: loginHome)
        return try CodexCommandRunner.runSync(
            runtime: context.runtime,
            arguments: arguments,
            environment: context.environment
        )
    }

    func runCodexCaptureAsync(arguments: [String], loginHome: String? = nil) async throws -> ProcessResult {
        let context = try resolvedRuntimeContext(loginHome: loginHome)
        return try await CodexCommandRunner.runAsync(
            runtime: context.runtime,
            arguments: arguments,
            environment: context.environment
        )
    }

    func makeCodexShellCommand(arguments: [String], loginHome: String? = nil) throws -> String {
        let environment = baseEnvironment(loginHome: loginHome)
        let runtime = try resolveCodexRuntime(environment: environment)
        let parts = [runtime.executableURL.path] + runtime.prefixArguments + arguments
        return parts.map(shellQuote).joined(separator: " ")
    }

    func baseEnvironment(loginHome: String? = nil) -> [String: String] {
        var env = processEnvironmentProvider()
        env["PATH"] = mergedExecutableSearchPath(for: env)
        applySandboxEnvironment(to: &env, loginHome: loginHome)
        return env
    }

    func mergedExecutableSearchPath(for environment: [String: String]) -> String {
        ExecutableSearchPath.merge([
            resolvedLoginShellPath(using: environment),
            environment["PATH"],
            ExecutableSearchPath.fallback,
        ])
    }

    func applySandboxEnvironment(to env: inout [String: String], loginHome: String? = nil) {
        let paths = currentPaths(loginHome: loginHome)
        env["HOME"] = paths.homeDir
        env["MULTICODEX_HOME"] = paths.multicodexHome
    }

    func terminalPreambleLines(loginHome: String? = nil) -> [String] {
        let paths = currentPaths(loginHome: loginHome)
        let shellPath = mergedExecutableSearchPath(for: processEnvironmentProvider())
        return [
            "export PATH=\(shellQuote(shellPath))",
            "export HOME=\(shellQuote(paths.homeDir))",
            "export MULTICODEX_HOME=\(shellQuote(paths.multicodexHome))",
        ]
    }

    private func resolvedRuntimeContext(loginHome: String? = nil) throws -> (runtime: CodexRuntime, environment: [String: String]) {
        let environment = baseEnvironment(loginHome: loginHome)
        let runtime = try resolveCodexRuntime(environment: environment)
        return (runtime, environment)
    }

}
