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

    func makeTerminalCodexLoginCommand(accountName: String, firstTime: Bool) throws -> String {
        let appName = shellQuote("MultiCodex")
        let account = shellQuote(accountName)
        let codexLoginCommand = try makeCodexShellCommand(arguments: ["login"])

        var lines = terminalPreambleLines()
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
        let runtime = try CodexRuntimeResolver.resolve(
            customCodexPath: customCodexPath,
            fileManager: fileManager,
            environment: ProcessInfo.processInfo.environment
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

    func runCodexCapture(arguments: [String]) throws -> ProcessResult {
        let runtime = try resolveCodexRuntime()
        return try CodexCommandRunner.runSync(
            runtime: runtime,
            arguments: arguments,
            environment: baseEnvironment()
        )
    }

    func runCodexCaptureAsync(arguments: [String]) async throws -> ProcessResult {
        let runtime = try resolveCodexRuntime()
        return try await CodexCommandRunner.runAsync(
            runtime: runtime,
            arguments: arguments,
            environment: baseEnvironment()
        )
    }

    func makeCodexShellCommand(arguments: [String]) throws -> String {
        let runtime = try resolveCodexRuntime()
        let parts = [runtime.executableURL.path] + runtime.prefixArguments + arguments
        return parts.map(shellQuote).joined(separator: " ")
    }

    func baseEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let existingPath = env["PATH"], !existingPath.contains("/opt/homebrew/bin") {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + existingPath
        }
        applySandboxEnvironment(to: &env)
        return env
    }

    func applySandboxEnvironment(to env: inout [String: String]) {
        let paths = currentPaths()
        env["HOME"] = paths.homeDir
        env["MULTICODEX_HOME"] = paths.multicodexHome
    }

    func terminalPreambleLines() -> [String] {
        let paths = currentPaths()
        return [
            "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"",
            "export HOME=\(shellQuote(paths.homeDir))",
            "export MULTICODEX_HOME=\(shellQuote(paths.multicodexHome))",
        ]
    }

}
