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

        let ttlSeconds = Self.normalizedLimitsCacheTTLSeconds(limitsCacheTTLSeconds)
        var results: [LimitsResult] = []
        var errors: [LimitsErrorEntry] = []
        var needsLive: [String] = []

        for account in targets {
            if !refreshLive, let cached = try getCachedLimits(account: account, ttlMs: Double(ttlSeconds * 1000), paths: paths) {
                let ageSec = Int((cached.ageMs / 1000.0).rounded())
                results.append(LimitsResult(account: account, source: "cached", snapshot: cached.snapshot, ageSec: ageSec))
            } else {
                needsLive.append(account)
            }
        }

        guard !needsLive.isEmpty else {
            return LimitsPayload(results: results, errors: [])
        }

        // Split accounts into managed-home (parallel-safe) and legacy (must be serial).
        // Only treat accounts as managed if the managed-home migration has been completed
        // for THIS config directory. This prevents stale global managed homes from
        // interfering with sandbox/legacy service instances.
        let migrationMarker = URL(fileURLWithPath: paths.multicodexHome)
            .appendingPathComponent(".managed-migration-complete")
        let migrationCompleted = FileManager.default.fileExists(atPath: migrationMarker.path)

        let managedAccounts: [String]
        let legacyAccounts: [String]
        if migrationCompleted {
            managedAccounts = needsLive.filter { account in
                guard let homeURL = ManagedCodexHomeFactory.homeURL(for: account, multicodexHome: paths.multicodexHome) else { return false }
                return (try? ManagedCodexHomeFactory.readAuthData(from: homeURL)) != nil
            }
            legacyAccounts = needsLive.filter { !managedAccounts.contains($0) }
        } else {
            managedAccounts = []
            legacyAccounts = needsLive
        }

        // Parallel fetch for isolated managed-home accounts only
        if !managedAccounts.isEmpty {
            let parallelResults = fetchManagedLimitsParallel(accounts: managedAccounts, paths: paths)
            results.append(contentsOf: parallelResults.results)
            errors.append(contentsOf: parallelResults.errors)
        }

        // Serial fetch for legacy accounts that require auth swapping
        if !legacyAccounts.isEmpty {
            let serialResults = fetchLimitsSerial(targets: legacyAccounts, paths: paths)
            results.append(contentsOf: serialResults.results)
            errors.append(contentsOf: serialResults.errors)
        }

        return LimitsPayload(results: results, errors: errors)
    }

    /// Parallel fetch ONLY for accounts with managed homes.
    /// These accounts read auth from their isolated directory — no global auth swap needed.
    private func fetchManagedLimitsParallel(accounts: [String], paths: PathContext) -> (results: [LimitsResult], errors: [LimitsErrorEntry]) {
        var results: [LimitsResult] = []
        var errors: [LimitsErrorEntry] = []

        let group = DispatchGroup()
        let lock = NSLock()

        for account in accounts {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let (result, error) = self.fetchManagedAccountLimits(account, paths: paths)
                lock.lock()
                if let result { results.append(result) }
                if let error { errors.append(error) }
                lock.unlock()
                group.leave()
            }
        }

        _ = group.wait(timeout: .now() + 60)

        MultiCodexLog.log(
            .refresh,
            level: .info,
            "Managed parallel fetch completed",
            metadata: ["accounts": "\(accounts.count)", "results": "\(results.count)", "errors": "\(errors.count)"]
        )

        return (results: results, errors: errors)
    }

    /// Fetch limits for a single managed-home account in isolation.
    /// Does NOT touch global auth. Uses the managed home's auth.json directly.
    private func fetchManagedAccountLimits(_ account: String, paths: PathContext) -> (LimitsResult?, LimitsErrorEntry?) {
        guard let homeURL = ManagedCodexHomeFactory.homeURL(for: account, multicodexHome: paths.multicodexHome) else {
            return (nil, LimitsErrorEntry(account: account, message: "No managed home found"))
        }

        let managedAuthPath = homeURL.appendingPathComponent("auth.json").path

        // Try API fetch with managed auth
        do {
            let snapshot = try fetchRateLimitsViaApiForAuthPath(managedAuthPath)
            try? setCachedLimits(account: account, snapshot: snapshot, provider: "managed-api", paths: paths)
            return (LimitsResult(account: account, source: "live-managed", snapshot: snapshot, ageSec: nil), nil)
        } catch {
            MultiCodexLog.log(.refresh, level: .debug, "Managed API fetch failed for \(account): \(error.localizedDescription)")
        }

        return (nil, LimitsErrorEntry(account: account, message: "Managed API fetch failed for \(account)"))
    }

    private func fetchLimitsSerial(targets: [String], paths: PathContext) -> (results: [LimitsResult], errors: [LimitsErrorEntry]) {
        var results: [LimitsResult] = []
        var errors: [LimitsErrorEntry] = []

        for account in targets {
            // Legacy path: try API then RPC with auth swapping
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
                try? setCachedLimits(account: account, snapshot: snapshot, provider: "api", paths: paths)
                results.append(LimitsResult(account: account, source: "live-api", snapshot: snapshot, ageSec: nil))
                continue
            }

            let rpcResult: RateLimitSnapshot?
            let rpcError: Error?
            do {
                rpcResult = try withAccountAuth(account: account, forceLock: false, restorePreviousAuth: true, paths: paths) {
                    try self.fetchRateLimitsViaRpc()
                }
                rpcError = nil
            } catch {
                rpcResult = nil
                rpcError = error
            }

            if let snapshot = rpcResult {
                try? setCachedLimits(account: account, snapshot: snapshot, provider: "rpc", paths: paths)
                results.append(LimitsResult(account: account, source: "live-rpc", snapshot: snapshot, ageSec: nil))
                continue
            }

            let apiMessage = apiError?.localizedDescription ?? "unknown"
            let rpcMessage = rpcError?.localizedDescription ?? "unknown"
            errors.append(LimitsErrorEntry(account: account, message: "API failed (\(apiMessage)); RPC fallback failed (\(rpcMessage))"))
        }

        return (results: results, errors: errors)
    }

    func fetchRateLimitsViaRpc() throws -> RateLimitSnapshot {
        do {
            return try fetchRateLimitsViaPersistentRpc()
        } catch {
            MultiCodexLog.log(.rpc, level: .debug, "Persistent RPC failed, falling back to one-shot RPC: \(error.localizedDescription)")
            return try fetchRateLimitsViaOneShotRpc()
        }
    }

    private func fetchRateLimitsViaPersistentRpc() throws -> RateLimitSnapshot {
        let paths = currentPaths()
        var environment = baseEnvironment()
        if let fingerprint = authFingerprint(at: paths.defaultCodexAuthPath) {
            environment["MULTICODEX_AUTH_FINGERPRINT"] = fingerprint
        }
        let semaphore = DispatchSemaphore(value: 0)
        var response: Result<[String: Any], Error>?

        Task {
            do {
                let payload = try await CodexRPCSession.shared.fetchRateLimits(
                    scopedHomePath: paths.defaultCodexHome,
                    customCodexPath: customCodexPath,
                    environment: environment
                )
                response = .success(payload)
            } catch {
                response = .failure(error)
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 12) == .success else {
            throw CodexAccountServiceError(message: "Codex persistent RPC timed out while fetching rate limits.")
        }

        switch response {
        case .success(let payload):
            return try decodeRateLimitsRPCMessage(payload)
        case .failure(let error):
            throw error
        case nil:
            throw CodexAccountServiceError(message: "Codex persistent RPC returned no response.")
        }
    }

    private func authFingerprint(at path: String) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return "missing"
        }

        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size):\(modifiedAt)"
    }

    private func fetchRateLimitsViaOneShotRpc() throws -> RateLimitSnapshot {
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
            if let recovered = recoverSnapshotFromRPCError(responseError) {
                MultiCodexLog.log(.rpc, level: .info, "Recovered usage from RPC error body")
                return recovered
            }
            throw CodexAccountServiceError(message: "Codex RPC error: \(responseError)")
        }

        guard let message = responseMessage else {
            let stderrText = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if stderrText.isEmpty {
                throw CodexAccountServiceError(message: "Codex RPC returned no response.")
            }
            throw CodexAccountServiceError(message: stderrText)
        }

        return try decodeRateLimitsRPCMessage(message)
    }

    private func decodeRateLimitsRPCMessage(_ message: [String: Any]) throws -> RateLimitSnapshot {
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

    func recoverSnapshotFromRPCError(_ errorMessage: String) -> RateLimitSnapshot? {
        guard let jsonString = extractJSONObject(after: "body=", in: errorMessage),
              let jsonData = jsonString.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return nil
        }

        let nowSec = Int(Date().timeIntervalSince1970)
        let rateLimit = asObject(body["rate_limit"])
        let primaryWindow = asObject(rateLimit?["primary_window"])
        let secondaryWindow = asObject(rateLimit?["secondary_window"])
        let reviewWindow = asObject(asObject(body["code_review_rate_limit"])?["primary_window"])

        let primary = buildWindow(
            usedPercent: readNumber(primaryWindow?["used_percent"]),
            windowDurationMins: readDurationMins(window: primaryWindow, fallbackMins: 300),
            resetsAt: readResetsAt(window: primaryWindow, nowSec: nowSec)
        )

        let secondaryCandidate = secondaryWindow ?? reviewWindow
        let secondary = buildWindow(
            usedPercent: readNumber(secondaryWindow?["used_percent"]) ?? readNumber(reviewWindow?["used_percent"]),
            windowDurationMins: readDurationMins(window: secondaryCandidate, fallbackMins: 10_080),
            resetsAt: readResetsAt(window: secondaryCandidate, nowSec: nowSec)
        )

        let creditsObject = asObject(body["credits"])
        let hasCredits = readBoolean(creditsObject?["has_credits"])
        let unlimited = readBoolean(creditsObject?["unlimited"])
        let balance = readNumber(creditsObject?["balance"]).map(numberString)
        let credits: CreditsSnapshot?
        if hasCredits != nil || unlimited != nil || balance != nil {
            credits = CreditsSnapshot(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
        } else {
            credits = nil
        }

        guard primary != nil || secondary != nil || credits != nil else {
            return nil
        }

        MultiCodexLog.log(
            .rpc,
            level: .info,
            "Recovered rate limit data from RPC error body",
            metadata: [
                "primary": primary == nil ? "no" : "yes",
                "secondary": secondary == nil ? "no" : "yes",
                "credits": credits == nil ? "no" : "yes",
            ]
        )
        return RateLimitSnapshot(primary: primary, secondary: secondary, credits: credits)
    }

    func extractJSONObject(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else {
            return nil
        }

        let suffix = text[markerRange.upperBound...]
        guard let start = suffix.firstIndex(of: "{") else {
            return nil
        }

        var depth = 0
        var inString = false
        var isEscaped = false

        for index in suffix[start...].indices {
            let character = suffix[index]

            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(suffix[start...index])
                }
            default:
                break
            }
        }

        return nil
    }

}
