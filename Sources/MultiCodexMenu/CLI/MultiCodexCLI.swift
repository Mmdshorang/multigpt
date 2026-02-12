import Foundation

final class MultiCodexCLI {
    static let limitsCacheTTLSeconds = 300

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let commandDisplay: String
    }

    private let fileManager = FileManager.default

    var customNodePath: String?
    var sandboxHomeDirectory: String?
    var sandboxMulticodexHomeDirectory: String?
    private(set) var resolutionHint: String?

    func fetchAccounts() async throws -> AccountsListPayload {
        let envelope: CommandEnvelope<AccountsListPayload> = try await runEnvelope(arguments: ["accounts", "list", "--json"])
        if let data = envelope.data {
            return data
        }
        throw makeCommandError(from: envelope, fallback: "Failed to load accounts.")
    }

    func fetchLimits(refreshLive: Bool) async throws -> LimitsPayload {
        var args = ["limits", "--json", "--ttl", String(Self.limitsCacheTTLSeconds)]
        if refreshLive {
            args.append("--refresh")
        }

        let envelope: CommandEnvelope<LimitsPayload> = try await runEnvelope(arguments: args)
        if let data = envelope.data {
            return data
        }
        throw makeCommandError(from: envelope, fallback: "Failed to load usage limits.")
    }

    func switchAccount(name: String) async throws {
        let envelope: CommandEnvelope<SwitchAccountPayload> = try await runEnvelope(arguments: ["accounts", "use", name, "--json"])
        if envelope.ok {
            return
        }
        throw makeCommandError(from: envelope, fallback: "Failed to switch account to \(name).")
    }

    func addAccount(name: String) async throws -> AddAccountPayload {
        let envelope: CommandEnvelope<AddAccountPayload> = try await runEnvelope(arguments: ["accounts", "add", name, "--json"])
        if let data = envelope.data {
            return data
        }
        throw makeCommandError(from: envelope, fallback: "Failed to add account \(name).")
    }

    func removeAccount(name: String, deleteData: Bool) async throws -> RemoveAccountPayload {
        var args = ["accounts", "remove", name, "--json"]
        if deleteData {
            args.insert("--delete-data", at: 3)
        }

        let envelope: CommandEnvelope<RemoveAccountPayload> = try await runEnvelope(arguments: args)
        if let data = envelope.data {
            return data
        }
        throw makeCommandError(from: envelope, fallback: "Failed to remove account \(name).")
    }

    func renameAccount(from oldName: String, to newName: String) async throws -> RenameAccountPayload {
        let envelope: CommandEnvelope<RenameAccountPayload> = try await runEnvelope(arguments: ["accounts", "rename", oldName, newName, "--json"])
        if let data = envelope.data {
            return data
        }
        throw makeCommandError(from: envelope, fallback: "Failed to rename account \(oldName).")
    }

    func importDefaultAuth(into name: String) async throws -> ImportAccountPayload {
        let envelope: CommandEnvelope<ImportAccountPayload> = try await runEnvelope(arguments: ["accounts", "import", name, "--json"])
        if let data = envelope.data {
            return data
        }
        throw makeCommandError(from: envelope, fallback: "Failed to import auth for \(name).")
    }

    func fetchStatus(name: String) async throws -> AccountStatusPayload {
        let envelope: CommandEnvelope<AccountStatusPayload> = try await runEnvelope(arguments: ["status", name, "--json"])
        if let data = envelope.data {
            return data
        }
        throw makeCommandError(from: envelope, fallback: "Failed to check login status for \(name).")
    }

    func openLoginInTerminal(account name: String) throws {
        let command = try makeTerminalLoginCommand(account: name)
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(escapedCommand)\"",
        ]

        do {
            try process.run()
        } catch {
            throw MultiCodexCLIError(message: "Could not open Terminal for login: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MultiCodexCLIError(message: "Could not launch Terminal login session (exit \(process.terminationStatus)).")
        }
    }

    func openNewProfileLoginInTerminal(newProfileName name: String) throws {
        let command = try makeTerminalFirstLoginCommand(newProfileName: name)
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application \"Terminal\" to activate",
            "-e", "tell application \"Terminal\" to do script \"\(escapedCommand)\"",
        ]

        do {
            try process.run()
        } catch {
            throw MultiCodexCLIError(message: "Could not open Terminal for new profile login: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MultiCodexCLIError(message: "Could not launch Terminal new profile login session (exit \(process.terminationStatus)).")
        }
    }

    private func runEnvelope<T: Decodable>(arguments: [String]) async throws -> CommandEnvelope<T> {
        let result = try await run(arguments: arguments)

        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            let stderrText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = stderrText.isEmpty
                ? "No JSON output from command: \(result.commandDisplay)"
                : stderrText
            throw MultiCodexCLIError(message: message)
        }

        do {
            let decoded = try JSONDecoder().decode(CommandEnvelope<T>.self, from: Data(output.utf8))
            return decoded
        } catch {
            throw MultiCodexCLIError(
                message: "Could not parse multicodex JSON output. Command: \(result.commandDisplay). Output: \(output.prefix(200))"
            )
        }
    }

    private func run(arguments: [String]) async throws -> ProcessResult {
        let resolved = try resolveCommand()

        let result: ProcessResult = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = resolved.runtime.executableURL
            process.arguments = resolved.runtime.prefixArguments + [resolved.bundledCLIURL.path] + arguments

            var env = ProcessInfo.processInfo.environment
            if let existingPath = env["PATH"], !existingPath.contains("/opt/homebrew/bin") {
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + existingPath
            }
            self.applySandboxEnvironment(to: &env)
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                throw MultiCodexCLIError(message: "Could not run \(resolved.commandDisplay): \(error.localizedDescription)")
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr,
                commandDisplay: resolved.commandDisplay
            )
        }.value

        if result.exitCode != 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let stderrText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderrText.isEmpty {
                throw MultiCodexCLIError(message: stderrText)
            }
            throw MultiCodexCLIError(message: "Command failed: \(result.commandDisplay) (exit \(result.exitCode))")
        }

        return result
    }

    private func makeShellCommand(arguments: [String]) throws -> String {
        let resolved = try resolveCommand()
        let parts = [resolved.runtime.executableURL.path]
            + resolved.runtime.prefixArguments
            + [resolved.bundledCLIURL.path]
            + arguments
        return parts.map(shellQuote).joined(separator: " ")
    }

    private func makeTerminalLoginCommand(account name: String) throws -> String {
        let useCommand = try makeShellCommand(arguments: ["accounts", "use", name, "--json"])
        let importCommand = try makeShellCommand(arguments: ["accounts", "import", name, "--json"])
        let statusCommand = try makeShellCommand(arguments: ["status", name, "--json"])
        let appName = shellQuote("MultiCodex")
        let profileName = shellQuote(name)

        // Use codex login directly in Terminal for a native interactive browser flow.
        return (terminalPreambleLines() + [
            "echo \"Starting MultiCodex login flow...\"",
            "echo \"Profile: \(profileName)\"",
            "\(useCommand)",
            "USE_EXIT=$?",
            "if [ \"$USE_EXIT\" -ne 0 ]; then",
            "  echo \"Failed to prepare profile before login (exit $USE_EXIT).\"",
            "  open -a \(appName) >/dev/null 2>&1 || true",
            "  exit $USE_EXIT",
            "fi",
            "codex login",
            "LOGIN_EXIT=$?",
            "\(importCommand) || true",
            "\(statusCommand) || true",
            "if [ \"$LOGIN_EXIT\" -eq 0 ]; then",
            "  echo \"Login completed.\"",
            "else",
            "  echo \"Login failed (exit $LOGIN_EXIT).\"",
            "fi",
            "open -a \(appName) >/dev/null 2>&1 || true",
            "exit $LOGIN_EXIT",
        ]).joined(separator: "\n")
    }

    private func makeTerminalFirstLoginCommand(newProfileName name: String) throws -> String {
        let addCommand = try makeShellCommand(arguments: ["accounts", "add", name, "--json"])
        let importCommand = try makeShellCommand(arguments: ["accounts", "import", name, "--json"])
        let useCommand = try makeShellCommand(arguments: ["accounts", "use", name, "--json"])
        let statusCommand = try makeShellCommand(arguments: ["status", name, "--json"])
        let appName = shellQuote("MultiCodex")
        let profileName = shellQuote(name)

        return (terminalPreambleLines() + [
            "echo \"Starting first-time MultiCodex login...\"",
            "echo \"You will be able to rename profile \(profileName) later in Settings.\"",
            "codex login",
            "LOGIN_EXIT=$?",
            "if [ \"$LOGIN_EXIT\" -ne 0 ]; then",
            "  echo \"Login failed (exit $LOGIN_EXIT).\"",
            "  open -a \(appName) >/dev/null 2>&1 || true",
            "  exit $LOGIN_EXIT",
            "fi",
            "\(addCommand)",
            "ADD_EXIT=$?",
            "if [ \"$ADD_EXIT\" -ne 0 ]; then",
            "  echo \"Login worked, but profile creation failed (exit $ADD_EXIT).\"",
            "  open -a \(appName) >/dev/null 2>&1 || true",
            "  exit $ADD_EXIT",
            "fi",
            "\(importCommand)",
            "IMPORT_EXIT=$?",
            "if [ \"$IMPORT_EXIT\" -ne 0 ]; then",
            "  echo \"Profile created, but importing auth failed (exit $IMPORT_EXIT).\"",
            "  open -a \(appName) >/dev/null 2>&1 || true",
            "  exit $IMPORT_EXIT",
            "fi",
            "\(useCommand)",
            "USE_EXIT=$?",
            "if [ \"$USE_EXIT\" -ne 0 ]; then",
            "  echo \"Profile created, but switching failed (exit $USE_EXIT).\"",
            "  open -a \(appName) >/dev/null 2>&1 || true",
            "  exit $USE_EXIT",
            "fi",
            "\(statusCommand) || true",
            "echo \"Login complete. New profile: \(profileName)\"",
            "open -a \(appName) >/dev/null 2>&1 || true",
            "exit 0",
        ]).joined(separator: "\n")
    }

    private func resolveCommand() throws -> ResolvedCommand {
        let resolved = try CLIRuntimeResolver.resolveCommand(
            fileManager: fileManager,
            customNodePath: customNodePath
        )
        var hint = "Bundled CLI: \(resolved.bundledCLIURL.path) | Node: \(resolved.runtime.display)"
        if let home = sandboxHomeDirectory, !home.isEmpty {
            hint += " | HOME: \(home)"
        }
        if let multicodexHome = sandboxMulticodexHomeDirectory, !multicodexHome.isEmpty {
            hint += " | MULTICODEX_HOME: \(multicodexHome)"
        }
        resolutionHint = hint
        return resolved
    }

    func effectiveMulticodexHomePath() -> String {
        if let override = sandboxMulticodexHomeDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        if let envOverride = ProcessInfo.processInfo.environment["MULTICODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !envOverride.isEmpty {
            return envOverride
        }
        let home = effectiveHomeDirectory()
        return "\(home)/.config/multicodex"
    }

    private func effectiveHomeDirectory() -> String {
        if let override = sandboxHomeDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        if let envHome = ProcessInfo.processInfo.environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !envHome.isEmpty {
            return envHome
        }
        return NSHomeDirectory()
    }

    private func applySandboxEnvironment(to env: inout [String: String]) {
        if let home = sandboxHomeDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
            env["HOME"] = home
        }
        if let multicodexHome = sandboxMulticodexHomeDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !multicodexHome.isEmpty {
            env["MULTICODEX_HOME"] = multicodexHome
        }
    }

    private func terminalPreambleLines() -> [String] {
        var lines = [
            "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"",
        ]
        if let home = sandboxHomeDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
            lines.append("export HOME=\(shellQuote(home))")
        }
        if let multicodexHome = sandboxMulticodexHomeDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !multicodexHome.isEmpty {
            lines.append("export MULTICODEX_HOME=\(shellQuote(multicodexHome))")
        }
        return lines
    }

    private func makeCommandError<T>(from envelope: CommandEnvelope<T>, fallback: String) -> Error {
        if let message = envelope.error?.message {
            return MultiCodexCLIError(message: message)
        }
        return MultiCodexCLIError(message: fallback)
    }

    private func shellQuote(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}

struct MultiCodexCLIError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
