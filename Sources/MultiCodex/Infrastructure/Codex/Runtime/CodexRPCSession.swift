import Foundation

/// Persistent JSON-RPC client for the Codex CLI.
/// Maintains a long-lived `codex -s read-only -a untrusted app-server` process.
actor CodexRPCSession {
    static let shared = CodexRPCSession()

    enum SessionError: LocalizedError {
        case launchFailed(String)
        case notInitialized
        case requestFailed(String)
        case malformed(String)
        case processDied

        var errorDescription: String? {
            switch self {
            case .launchFailed(let msg): return "Codex RPC launch failed: \(msg)"
            case .notInitialized: return "Codex RPC session not initialized."
            case .requestFailed(let msg): return "Codex RPC error: \(msg)"
            case .malformed(let msg): return "Codex RPC malformed response: \(msg)"
            case .processDied: return "Codex RPC process exited."
            }
        }
    }

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stdoutBuffer = Data()
    private var nextID = 1
    private var initialized = false
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var scopedHomePath: String?

    func ensureReady(scopedHomePath: String? = nil) async throws {
        if self.scopedHomePath != scopedHomePath {
            shutdown()
            self.scopedHomePath = scopedHomePath
        }
        if let proc = process, proc.isRunning, initialized { return }
        try launch()
        try await initialize()
    }

    func fetchRateLimits(scopedHomePath: String? = nil) async throws -> [String: Any] {
        try await ensureReady(scopedHomePath: scopedHomePath)
        return try await request(method: "account/rateLimits/read")
    }

    func fetchAccount(scopedHomePath: String? = nil) async throws -> [String: Any] {
        try await ensureReady(scopedHomePath: scopedHomePath)
        return try await request(method: "account/read")
    }

    func shutdown() {
        guard let proc = process, proc.isRunning else { return }
        MultiCodexLog.log(.rpc, level: .info, "Shutting down RPC session")
        proc.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stdoutBuffer = Data()
        initialized = false
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: SessionError.processDied)
        }
        pendingRequests.removeAll()
    }

    // MARK: - Private

    private func launch() throws {
        shutdown()

        let runtime = try CodexRuntimeResolver.resolve(
            customCodexPath: nil,
            fileManager: .default,
            environment: ProcessInfo.processInfo.environment
        )
        let proc = Process()
        proc.executableURL = runtime.executableURL
        proc.arguments = runtime.prefixArguments + ["-s", "read-only", "-a", "untrusted", "app-server"]

        var env = ProcessInfo.processInfo.environment
        if let path = LoginShellPathResolver.resolvePath(from: env) {
            env["PATH"] = path
        }
        if let homePath = scopedHomePath {
            env["CODEX_HOME"] = homePath
        }
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw SessionError.launchFailed(error.localizedDescription)
        }

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stdoutBuffer = Data()
        self.initialized = false

        MultiCodexLog.log(
            .rpc,
            level: .info,
            "RPC session launched",
            metadata: ["codexHome": scopedHomePath ?? "system"]
        )
        startReading()
    }

    private func initialize() async throws {
        guard process?.isRunning == true else { throw SessionError.processDied }
        _ = try await request(method: "initialize", params: [
            "clientInfo": ["name": "multicodex-mac", "version": "0.5"],
        ])
        try sendNotification(method: "initialized")
        initialized = true
        MultiCodexLog.log(.rpc, level: .info, "RPC session initialized")
    }

    private func request(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        guard process?.isRunning == true else { throw SessionError.processDied }
        let id = nextID
        nextID += 1
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            do {
                try sendPayload(["id": id, "method": method, "params": params ?? [:]])
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendNotification(method: String) throws {
        try sendPayload(["method": method, "params": [:]])
    }

    private func sendPayload(_ payload: [String: Any]) throws {
        guard let stdin = stdinPipe?.fileHandleForWriting else {
            throw SessionError.notInitialized
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        stdin.write(data)
        stdin.write(Data([0x0A]))
    }

    private func startReading() {
        guard let stdout = stdoutPipe?.fileHandleForReading else { return }
        stdout.readabilityHandler = { [weak self] handle in
            let newData = handle.availableData
            guard !newData.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { await self?.processStdoutData(newData) }
        }
    }

    private func processStdoutData(_ data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = Data(stdoutBuffer[..<nl])
            stdoutBuffer.removeSubrange(...nl)
            guard !lineData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let id = json["id"] as? Int, let cont = pendingRequests.removeValue(forKey: id) {
                if let error = json["error"] as? [String: Any],
                   let msg = error["message"] as? String
                {
                    cont.resume(throwing: SessionError.requestFailed(msg))
                } else {
                    cont.resume(returning: json)
                }
            }
        }
    }
}
