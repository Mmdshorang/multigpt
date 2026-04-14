import Foundation

// RateLimitsFetcher
extension CodexAccountService {

    func fetchStatusNow(name: String) throws -> AccountStatusPayload {
        let account = normalizeAccountName(name)
        let paths = currentPaths()
        let config = try loadConfig(paths: paths)
        guard config.accounts.contains(account) else {
            throw CodexAccountServiceError(message: "Unknown account: \(account)")
        }

        let result = try withAccountAuth(account: account, forceLock: false, restorePreviousAuth: true, paths: paths) {
            try runCodexCapture(arguments: ["login", "status"])
        }

        let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try updateAccountMeta(account: account, paths: paths) { meta in
            meta.lastUsedAt = Self.nowISO()
            meta.lastLoginStatus = combined.isEmpty ? nil : combined
            meta.lastLoginCheckedAt = Self.nowISO()
        }

        return AccountStatusPayload(
            account: account,
            exitCode: Int(result.exitCode),
            stdout: result.stdout,
            stderr: result.stderr,
            output: combined,
            checkedAt: Self.nowISO()
        )
    }

    func fetchStatusForLoginHomeNow(_ homePath: String, accountName: String) throws -> AccountStatusPayload {
        let result = try runCodexCapture(arguments: ["login", "status"], loginHome: homePath)
        let combined = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        return AccountStatusPayload(
            account: accountName,
            exitCode: Int(result.exitCode),
            stdout: result.stdout,
            stderr: result.stderr,
            output: combined,
            checkedAt: Self.nowISO()
        )
    }

    func fetchLimitsNow(refreshLive: Bool) throws -> LimitsPayload {
        let paths = currentPaths()
        let config = try loadConfig(paths: paths)
        let targets = config.accounts.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var results: [LimitsResult] = []
        var errors: [LimitsErrorEntry] = []

        for account in targets {
            // 1. Check cache if not forcing live refresh
            let ttlSeconds = Self.normalizedLimitsCacheTTLSeconds(limitsCacheTTLSeconds)
            if !refreshLive, let cached = try getCachedLimits(account: account, ttlMs: Double(ttlSeconds * 1000), paths: paths) {
                let ageSec = Int((cached.ageMs / 1000.0).rounded())
                results.append(
                    LimitsResult(
                        account: account,
                        source: "cached",
                        snapshot: cached.snapshot,
                        ageSec: ageSec
                    )
                )
                continue
            }

            // 2. Try API fetch
            let apiResult: RateLimitSnapshot?
            let apiError: Error?
            do {
                apiResult = try fetchRateLimitsViaApiForAuthPath(paths.accountAuthPath(account))
                apiError = nil
            } catch {
                apiResult = nil
                apiError = error
            }

            if let snapshot = apiResult {
                try setCachedLimits(account: account, snapshot: snapshot, provider: "api", paths: paths)
                results.append(
                    LimitsResult(
                        account: account,
                        source: "live-api",
                        snapshot: snapshot,
                        ageSec: nil
                    )
                )
                continue
            }

            // 3. Fallback to RPC fetch
            let rpcResult: RateLimitSnapshot?
            let rpcError: Error?
            do {
                rpcResult = try withAccountAuth(account: account, forceLock: false, restorePreviousAuth: true, paths: paths) {
                    try fetchRateLimitsViaRpc()
                }
                rpcError = nil
            } catch {
                rpcResult = nil
                rpcError = error
            }

            if let snapshot = rpcResult {
                try setCachedLimits(account: account, snapshot: snapshot, provider: "rpc", paths: paths)
                results.append(
                    LimitsResult(
                        account: account,
                        source: "live-rpc",
                        snapshot: snapshot,
                        ageSec: nil
                    )
                )
                continue
            }

            // 4. Record error if both API and RPC failed
            let apiMessage = apiError?.localizedDescription ?? "unknown"
            let rpcMessage = rpcError?.localizedDescription ?? "unknown"
            errors.append(
                LimitsErrorEntry(
                    account: account,
                    message: "API failed (\(apiMessage)); RPC fallback failed (\(rpcMessage))"
                )
            )
        }

        return LimitsPayload(results: results, errors: errors)
    }

    func fetchRateLimitsViaRpc() throws -> RateLimitSnapshot {
        let runtime = try resolveCodexRuntime()
        let process = Process()
        process.executableURL = runtime.executableURL
        process.arguments = runtime.prefixArguments + ["-s", "read-only", "-a", "untrusted", "app-server"]
        process.environment = baseEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CodexAccountServiceError(message: "Could not run \(runtime.display): \(error.localizedDescription)")
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdinHandle = stdinPipe.fileHandleForWriting

        let responseSemaphore = DispatchSemaphore(value: 0)
        let stateLock = NSLock()

        var stdoutBuffer = ""
        var stderrBuffer = ""
        var didSignal = false
        var responseMessage: [String: Any]?
        var responseError: String?

        func signalOnce() {
            stateLock.lock()
            defer { stateLock.unlock() }
            if !didSignal {
                didSignal = true
                responseSemaphore.signal()
            }
        }

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let text = String(data: data, encoding: .utf8) ?? ""

            stateLock.lock()
            stdoutBuffer += text
            while let nl = stdoutBuffer.firstIndex(of: "\n") {
                let line = String(stdoutBuffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutBuffer = String(stdoutBuffer[stdoutBuffer.index(after: nl)...])
                guard !line.isEmpty else { continue }

                guard let raw = line.data(using: .utf8),
                      let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
                else {
                    continue
                }

                let id = payload["id"] as? Int
                if id == 2 {
                    if let err = payload["error"] as? [String: Any], let message = err["message"] as? String {
                        responseError = message
                    } else {
                        responseMessage = payload
                    }
                    if !didSignal {
                        didSignal = true
                        responseSemaphore.signal()
                    }
                }
            }
            stateLock.unlock()
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            stateLock.lock()
            stderrBuffer += text
            stateLock.unlock()
        }

        do {
            try RateLimitsRPCClient.writeMessage(
                ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "multicodex-mac", "version": "native"]]],
                to: stdinHandle
            )
            try RateLimitsRPCClient.writeMessage(["method": "initialized", "params": [:]], to: stdinHandle)
            try RateLimitsRPCClient.writeMessage(["id": 2, "method": "account/rateLimits/read", "params": [:]], to: stdinHandle)
        } catch {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw CodexAccountServiceError(message: "Could not write Codex RPC request: \(error.localizedDescription)")
        }

        let waitResult = responseSemaphore.wait(timeout: .now() + 12)

        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        try? stdinHandle.close()

        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        if waitResult == .timedOut {
            let stderrText = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                throw CodexAccountServiceError(message: "Codex RPC timed out while fetching rate limits.")
            }
            throw CodexAccountServiceError(message: "Codex RPC timed out: \(stderrText)")
        }

        if let responseError, !responseError.isEmpty {
            throw CodexAccountServiceError(message: "Codex RPC error: \(responseError)")
        }

        guard let message = responseMessage else {
            let stderrText = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                throw CodexAccountServiceError(message: "Codex RPC returned no response.")
            }
            throw CodexAccountServiceError(message: stderrText)
        }

        let result = message["result"] as? [String: Any]
        let rateLimitsValue = result?["rateLimits"]

        if rateLimitsValue is NSNull || rateLimitsValue == nil {
            return RateLimitSnapshot(primary: nil, secondary: nil, credits: nil)
        }

        guard let rateLimitsObject = rateLimitsValue as? [String: Any] else {
            throw CodexAccountServiceError(message: "Unexpected Codex RPC payload for rate limits.")
        }

        let data = try JSONSerialization.data(withJSONObject: rateLimitsObject, options: [])
        return try decoder.decode(RateLimitSnapshot.self, from: data)
    }

}
