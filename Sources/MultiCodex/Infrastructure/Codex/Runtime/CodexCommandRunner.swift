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
        let state = AsyncProcessState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.start(
                    runtime: runtime,
                    arguments: arguments,
                    environment: environment,
                    continuation: continuation
                )
            }
        } onCancel: {
            state.cancel()
        }
    }
}

private final class AsyncProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var continuation: CheckedContinuation<CodexCommandResult, Error>?
    private var isCancelled = false
    private var didComplete = false

    func start(
        runtime: CodexRuntimeDescriptor,
        arguments: [String],
        environment: [String: String],
        continuation: CheckedContinuation<CodexCommandResult, Error>
    ) {
        let process = Process()
        process.executableURL = runtime.executableURL
        process.arguments = runtime.prefixArguments + arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        lock.lock()
        if didComplete {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.continuation = continuation
        let shouldCancelImmediately = isCancelled
        lock.unlock()

        process.terminationHandler = { [weak self] process in
            self?.complete(process: process)
        }

        do {
            try process.run()
            if shouldCancelImmediately {
                process.terminate()
            }
        } catch {
            process.terminationHandler = nil
            finish(.failure(CodexAccountServiceError(message: "Could not run \(runtime.display): \(error.localizedDescription)")))
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let process = process
        lock.unlock()

        guard let process else {
            finish(.failure(CancellationError()))
            return
        }

        if process.isRunning {
            process.terminate()
        }
    }

    private func complete(process: Process) {
        let stdoutData = stdoutPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let stderrData = stderrPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        lock.lock()
        let cancelled = isCancelled
        lock.unlock()

        if cancelled {
            finish(.failure(CancellationError()))
        } else {
            finish(.success(CodexCommandResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)))
        }
    }

    private func finish(_ result: Result<CodexCommandResult, Error>) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        let continuation = continuation
        self.continuation = nil
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        lock.unlock()

        switch result {
        case let .success(value):
            continuation?.resume(returning: value)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }
}
