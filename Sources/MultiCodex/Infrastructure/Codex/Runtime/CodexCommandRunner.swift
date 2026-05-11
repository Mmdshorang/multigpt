import Foundation

struct CodexCommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum CodexCommandRunner {
    static func runSync(
        runtime: CodexRuntimeDescriptor,
        arguments: [String],
        environment: [String: String]
    ) throws -> CodexCommandResult {
        let process = Process()
        process.executableURL = runtime.executableURL
        process.arguments = runtime.prefixArguments + arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CodexAccountServiceError(message: "Could not run \(runtime.display): \(error.localizedDescription)")
        }

        // Read pipe data BEFORE waitUntilExit to avoid pipe buffer deadlock.
        // If the child writes more than the pipe buffer size (~64KB), it will
        // block waiting for the reader. Reading first prevents this.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return CodexCommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    static func runAsync(
        runtime: CodexRuntimeDescriptor,
        arguments: [String],
        environment: [String: String]
    ) async throws -> CodexCommandResult {
        let process = Process()
        process.executableURL = runtime.executableURL
        process.arguments = runtime.prefixArguments + arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                continuation.resume(
                    returning: CodexCommandResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    )
                )
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: CodexAccountServiceError(message: "Could not run \(runtime.display): \(error.localizedDescription)"))
            }
        }
    }
}
