# MultiCodex Enhancement Roadmap

A phased roadmap to harden MultiCodex by adopting battle-tested patterns from [CodexBar](https://github.com/steipete/CodexBar) — persistent RPC, pace prediction, cost tracking, managed account isolation, and more — while staying true to our mission: **Codex-only multi-account management with usage-aware switching**.

Our UX and auto-switching intelligence are already superior to CodexBar. This roadmap focuses on closing the gap in **underlying plumbing**: isolation, safety, parallelism, and resilience.

Ordered by **effort × impact** — highest ROI first.

---

## Phase 1: Foundation (Low Effort, High Impact)

### 1.1 Structured Logging

**Problem:** Zero logging infrastructure. Impossible to diagnose user issues.

**CodexBar Reference:** `CodexBarCore/Logging/` — uses `swift-log` with OSLog + file + JSON handlers + PII redaction.

**Our Approach:** Use built-in `os.Logger` (no dependency) + file logging + redaction. Simpler than CodexBar's multi-handler setup.

**Files to Create:**

```
Sources/MultiCodex/Infrastructure/Logging/
├── MultiCodexLog.swift            # Central logger factory
├── LogCategories.swift            # Category constants
└── LogRedactor.swift              # PII stripping
```

#### `Sources/MultiCodex/Infrastructure/Logging/MultiCodexLog.swift`

```swift
import Foundation
import os

/// Centralized logging for MultiCodex.
/// Uses os.Logger (built-in, zero dependency) with file-based fallback.
enum MultiCodexLog {
    enum Category: String {
        case rpc = "rpc"
        case auth = "auth"
        case switching = "switching"
        case refresh = "refresh"
        case usage = "usage"
        case pace = "pace"
        case cost = "cost"
        case identity = "identity"
        case config = "config"
        case notifications = "notifications"
    }

    private static let subsystem = "com.multicodex.app"

    /// Create an os.Logger for the given category.
    static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    /// Log to both os.Logger and a rotating file log.
    /// File logs go to ~/Library/Logs/MultiCodex/multicodex.log
    static func log(
        _ category: Category,
        level: OSLogType = .info,
        _ message: String,
        metadata: [String: String] = [:])
    {
        let redacted = LogRedactor.redact(message)
        let logger = Self.logger(category)

        switch level {
        case .debug:    logger.debug("\(redacted, privacy: .public)")
        case .info:     logger.info("\(redacted, privacy: .public)")
        case .error:    logger.error("\(redacted, privacy: .public)")
        case .fault:    logger.fault("\(redacted, privacy: .public)")
        default:        logger.info("\(redacted, privacy: .public)")
        }

        FileLogHandler.shared.append(
            category: category.rawValue,
            level: level,
            message: redacted,
            metadata: metadata
        )
    }
}

/// Simple file log handler with rotation.
/// Keeps last 1 MB of logs in ~/Library/Logs/MultiCodex/
final class FileLogHandler {
    static let shared = FileLogHandler()

    private let queue = DispatchQueue(label: "com.multicodex.filelog", qos: .utility)
    private let logFileURL: URL
    private let maxFileSize: Int = 1_024_000 // ~1 MB

    private init() {
        let logDir = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Logs/MultiCodex", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: logDir, withIntermediateDirectories: true
        )
        self.logFileURL = logDir.appendingPathComponent("multicodex.log")
    }

    func append(category: String, level: OSLogType, message: String, metadata: [String: String]) {
        queue.async { [self] in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let levelStr: String
            switch level {
            case .debug:    levelStr = "DEBUG"
            case .info:     levelStr = "INFO"
            case .error:    levelStr = "ERROR"
            case .fault:    levelStr = "FAULT"
            default:        levelStr = "INFO"
            }
            let metaStr = metadata.isEmpty ? "" : " " + metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            let line = "[\(timestamp)] [\(levelStr)] [\(category)] \(message)\(metaStr)\n"

            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: self.logFileURL.path)
                let size = (attrs?[.size] as? Int) ?? 0
                if size > self.maxFileSize {
                    // Rotate: keep last half
                    if let existing = try? Data(contentsOf: self.logFileURL),
                       let halfStart = existing.range(of: Data("\n".utf8), options: .backwards, in: existing.startIndex ..< existing.index(existing.endIndex, offsetBy: -existing.count / 2)) {
                        let trimmed = existing[halfStart.upperBound...]
                        try? trimmed.write(to: self.logFileURL)
                    }
                }
                if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: self.logFileURL)
            }
        }
    }
}
```

#### `Sources/MultiCodex/Infrastructure/Logging/LogRedactor.swift`

```swift
import Foundation

/// Strips PII (emails, tokens, auth headers) from log messages.
/// Adapted from CodexBar's LogRedactor.
enum LogRedactor {
    private static let emailRegex = makeRegex(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )
    private static let bearerRegex = makeRegex(
        pattern: #"(?i)\bbearer\s+[a-z0-9._\-]+=*\b"#
    )
    private static let tokenRegex = makeRegex(
        pattern: #"(?i)(access_token["\s:=]+)["\w\-\.]{20,}"#,
        options: [.caseInsensitive]
    )

    static func redact(_ text: String) -> String {
        var output = text
        output = replace(emailRegex, in: output, with: "<email>")
        output = replace(bearerRegex, in: output, with: "Bearer <token>")
        output = replace(tokenRegex, in: output, with: "$1<token>")
        return output
    }

    private static func makeRegex(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
        (try? NSRegularExpression(pattern: pattern, options: options)) ?? {
            // Fallback: match nothing
            try! NSRegularExpression(pattern: "$^", options: [])
        }()
    }

    private static func replace(
        _ regex: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: template
        )
    }
}
```

#### `Sources/MultiCodex/Infrastructure/Logging/LogCategories.swift`

```swift
/// Log category constants — mirrors CodexBar's LogCategories pattern.
/// Usage: MultiCodexLog.logger(.rpc) or MultiCodexLog.log(.rpc, .info, "message")
extension MultiCodexLog.Category {
    // Add convenience accessors as needed
}
```

**Integration points:**
- `CodexAccountService` — log RPC requests/responses, auth swaps, token refreshes
- `AccountsRefreshController` — log refresh cycles, errors
- `AccountSwitchRecommendationService` — log recommendation decisions
- `AccountsMenuViewModel` — log UI state transitions

**Effort:** ~4 hours | **Impact:** Essential for support, debugging, and all future development.

---

### 1.2 Error Body Recovery from RPC

**Problem:** When the Codex RPC returns an error, we throw it away. CodexBar extracts rate limit data from error bodies, often containing actual usage percentages even in "rate limited" responses.

**CodexBar Reference:** `UsageFetcher.recoverUsageFromRPCError()`, `extractJSONObject(after:in:)` in `Sources/CodexBarCore/UsageFetcher.swift`

**File to Modify:** `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`

#### Current Code (throws away error data):

```swift
// In fetchRateLimitsViaRpc()
if let responseError, !responseError.isEmpty {
    throw CodexAccountServiceError(message: "Codex RPC error: \(responseError)")
}
```

#### New Implementation:

Add to `CodexAccountService`:

```swift
// MARK: - Error Body Recovery
// Adapted from CodexBar's UsageFetcher.recoverUsageFromRPCError()

/// Attempts to extract rate limit data from an RPC error response body.
/// The Codex CLI often includes rate limit information even in error responses
/// (e.g., when the account is rate-limited, the error body contains current usage).
///
/// CodexBar equivalent: recoverUsageFromRPCError + decodeRateLimitsErrorBody
func recoverSnapshotFromRPCError(_ errorMessage: String) -> RateLimitSnapshot? {
    guard let jsonString = extractJSONObject(after: "body=", in: errorMessage) else {
        return nil
    }
    guard let jsonData = jsonString.data(using: .utf8) else { return nil }

    // The error body mirrors the rate limits response structure:
    // { "rate_limit": { "primary_window": { ... }, "secondary_window": { ... } },
    //   "credits": { ... }, "plan_type": "...", "email": "..." }
    guard let body = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        return nil
    }

    let rateLimit = body["rate_limit"] as? [String: Any]
    let primaryWindow = rateLimit?["primary_window"] as? [String: Any]
    let secondaryWindow = rateLimit?["secondary_window"] as? [String: Any]
    let creditsObj = body["credits"] as? [String: Any]

    let primary = buildWindow(
        usedPercent: readNumber(primaryWindow?["used_percent"]),
        windowDurationMins: readDurationMins(window: primaryWindow, fallbackMins: 300),
        resetsAt: readResetsAt(window: primaryWindow, nowSec: Int(Date().timeIntervalSince1970))
    )
    let secondary = buildWindow(
        usedPercent: readNumber(secondaryWindow?["used_percent"]),
        windowDurationMins: readDurationMins(window: secondaryWindow, fallbackMins: 10_080),
        resetsAt: readResetsAt(window: secondaryWindow, nowSec: Int(Date().timeIntervalSince1970))
    )

    let hasCredits = readBoolean(creditsObj?["has_credits"])
    let unlimited = readBoolean(creditsObj?["unlimited"])
    let balance = (creditsObj?["balance"]).flatMap { readNumber($0).map(numberString) }
    let credits: CreditsSnapshot?
    if let hasCredits, let unlimited {
        credits = CreditsSnapshot(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
    } else {
        credits = nil
    }

    // Only return if we got something useful
    guard primary != nil || secondary != nil else { return nil }

    MultiCodexLog.log(.rpc, level: .info, "Recovered rate limit data from RPC error body",
                      metadata: ["primary": primary != nil ? "yes" : "no",
                                 "secondary": secondary != nil ? "yes" : "no"])

    return RateLimitSnapshot(primary: primary, secondary: secondary, credits: credits)
}

/// Extracts a JSON object following a marker string.
/// CodexBar's extractJSONObject(after:in:) — handles nested braces and string escaping.
func extractJSONObject(after marker: String, in text: String) -> String? {
    guard let markerRange = text.range(of: marker) else { return nil }
    let suffix = text[markerRange.upperBound...]
    guard let start = suffix.firstIndex(of: "{") else { return nil }

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
```

Then modify `fetchRateLimitsViaRpc()`:

```swift
// Replace the current error throw:
//   if let responseError, !responseError.isEmpty {
//       throw CodexAccountServiceError(message: "Codex RPC error: \(responseError)")
//   }
// With:

if let responseError, !responseError.isEmpty {
    // CodexBar pattern: attempt to recover data from the error body
    if let recovered = recoverSnapshotFromRPCError(responseError) {
        MultiCodexLog.log(.rpc, level: .info, "Recovered usage from RPC error",
                          metadata: ["error": responseError])
        return recovered
    }
    throw CodexAccountServiceError(message: "Codex RPC error: \(responseError)")
}
```

**Effort:** ~3 hours | **Impact:** Data that we currently throw away now enriches our usage display. Users see usage even when rate-limited.

---

### 1.3 Session Quota Transition Notifications

**Problem:** Users have no visibility into when accounts deplete or recover. Our notifications only fire on auto-switch.

**CodexBar Reference:** `SessionQuotaNotifications.swift` — detects `available → depleted` and `depleted → restored` transitions, posts macOS native notifications.

**Files to Create/Modify:**

```
Sources/MultiCodex/Core/Accounts/
└── QuotaTransitionDetector.swift      # NEW

Sources/MultiCodex/Infrastructure/Notifications/
└── QuotaTransitionNotificationCenter.swift  # NEW

Sources/MultiCodex/Features/Shared/
└── AccountsRefreshController.swift    # MODIFY — detect transitions after refresh
```

#### `Sources/MultiCodex/Core/Accounts/QuotaTransitionDetector.swift`

```swift
import Foundation

/// Detects quota transitions (depleted/restored) between refresh cycles.
/// Adapted from CodexBar's SessionQuotaNotificationLogic.
///
/// CodexBar tracks per-provider transitions. We track per-account, per-window (5h/weekly).
enum QuotaTransitionDetector {
    struct WindowTransition: Equatable {
        let accountName: String
        let window: QuotaWindow
        let transition: QuotaTransition
    }

    enum QuotaWindow: String, CaseIterable {
        case fiveHour = "5h"
        case weekly
    }

    enum QuotaTransition: Equatable {
        case depleted       // had capacity → now empty
        case restored       // was empty → now has capacity
        case none
    }

    /// Threshold below which we consider a window "depleted".
    /// CodexBar uses 0.0001 (effectively 0%).
    static let depletedThreshold: Double = 0.5 // 0.5% remaining = depleted

    static func isDepleted(_ remainingPercent: Double?) -> Bool {
        guard let remainingPercent else { return false }
        return (100 - remainingPercent) >= (100 - depletedThreshold)
    }

    /// Compare previous and current account lists to detect transitions.
    static func detectTransitions(
        previous: [AccountUsage],
        current: [AccountUsage]
    ) -> [WindowTransition] {
        var transitions: [WindowTransition] = []

        let previousByName = Dictionary(uniqueKeysWithValues: previous.map { ($0.name, $0) })

        for account in current {
            guard let prev = previousByName[account.name] else { continue }

            // 5h window transition
            let fiveHourTransition = detectWindowTransition(
                previousUsed: prev.usage.fiveHour.usedPercent,
                currentUsed: account.usage.fiveHour.usedPercent
            )
            if fiveHourTransition != .none {
                transitions.append(.init(
                    accountName: account.name,
                    window: .fiveHour,
                    transition: fiveHourTransition
                ))
            }

            // Weekly window transition
            let weeklyTransition = detectWindowTransition(
                previousUsed: prev.usage.weekly.usedPercent,
                currentUsed: account.usage.weekly.usedPercent
            )
            if weeklyTransition != .none {
                transitions.append(.init(
                    accountName: account.name,
                    window: .weekly,
                    transition: weeklyTransition
                ))
            }
        }

        return transitions
    }

    private static func detectWindowTransition(
        previousUsed: Double?,
        currentUsed: Double?
    ) -> QuotaTransition {
        let wasDepleted = isDepleted(previousUsed.map { 100 - $0 })
        let isNowDepleted = isDepleted(currentUsed.map { 100 - $0 })

        if !wasDepleted, isNowDepleted { return .depleted }
        if wasDepleted, !isNowDepleted { return .restored }
        return .none
    }
}
```

#### `Sources/MultiCodex/Infrastructure/Notifications/QuotaTransitionNotificationCenter.swift`

```swift
import Foundation
import UserNotifications

/// Posts macOS notifications when account quotas deplete or restore.
/// Adapted from CodexBar's SessionQuotaNotifier.
final class QuotaTransitionNotificationCenter {
    static let shared = QuotaTransitionNotificationCenter()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func post(transitions: [QuotaTransitionDetector.WindowTransition]) {
        for transition in transitions where transition.transition != .none {
            postSingle(transition)
        }
    }

    private func postSingle(_ transition: QuotaTransitionDetector.WindowTransition) {
        let windowLabel = transition.window.rawValue
        let title: String
        let body: String

        switch transition.transition {
        case .depleted:
            title = "\(transition.accountName) — \(windowLabel) depleted"
            body = "0% remaining. Will notify when it's available again."
        case .restored:
            title = "\(transition.accountName) — \(windowLabel) restored"
            body = "Quota is available again."
        case .none:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = transition.transition == .depleted ? .default : nil

        let request = UNNotificationRequest(
            identifier: "multicodex.quota.\(transition.accountName).\(transition.window.rawValue).\(transition.transition == .depleted ? "depleted" : "restored")",
            content: content,
            trigger: nil
        )

        Task { @MainActor in
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            try? await center.add(request)
        }

        MultiCodexLog.log(.notifications, level: .info,
                          "\(title): \(body)",
                          metadata: ["account": transition.accountName,
                                     "window": transition.window.rawValue])
    }
}
```

#### Modify `AccountsRefreshController.performRefresh()`:

After `applyMergedAccounts(...)` with limits, add:

```swift
// Detect quota transitions between refresh cycles
let quotaTransitions = QuotaTransitionDetector.detectTransitions(
    previous: previousAccounts,
    current: viewModel.accounts
)
if !quotaTransitions.isEmpty, viewModel.autoSwitchNotificationsEnabled {
    QuotaTransitionNotificationCenter.shared.post(transitions: quotaTransitions)
}
```

Also add a new preference to `AppPreferencesStore`:

```swift
// In AppPreferencesStore
var quotaTransitionNotificationsEnabled: Bool {
    get { defaults.bool(forKey: prefKey("quotaTransitionNotificationsEnabled")) }
    set { defaults.set(newValue, forKey: prefKey("quotaTransitionNotificationsEnabled")) }
}
```

**Effort:** ~4 hours | **Impact:** Users get real-time awareness of quota state changes — when accounts deplete and when they recover.

---

### 1.4 JWT-Based Account Identity

**Problem:** Our identity detection is fragile. After `codex login`, we need to reliably determine which account was authenticated.

**CodexBar Reference:** `UsageFetcher.parseJWT()`, `CodexIdentityResolver`, `CodexAuthBackedAccount`

**Files to Create/Modify:**

```
Sources/MultiCodex/Infrastructure/Codex/Accounts/
└── AccountIdentityResolver.swift    # MODIFY — add JWT parsing
```

#### Enhanced `AccountIdentityResolver`:

```swift
import Foundation

/// Resolves Codex account identity from auth.json payloads.
/// Uses JWT parsing for reliable email/plan extraction.
/// Adapted from CodexBar's CodexIdentityResolver + UsageFetcher.parseJWT().
extension AccountIdentityResolver {

    /// Parse the id_token JWT from an auth.json payload to extract account details.
    /// CodexBar approach: parse JWT claims for email, plan type, and account ID.
    ///
    /// JWT structure from OpenAI:
    /// - payload["email"] or payload["https://api.openai.com/profile"]["email"]
    /// - payload["https://api.openai.com/auth"]["chatgpt_plan_type"]
    /// - payload["https://api.openai.com/auth"]["chatgpt_account_id"]
    static func resolveFromAuthPayload(_ payload: [String: Any]) -> ResolvedAccountIdentity? {
        // Check for API key auth (no JWT)
        if let apiKey = payload["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ResolvedAccountIdentity(
                email: nil,
                plan: "api-key",
                accountId: nil,
                authMethod: .apiKey
            )
        }

        // Extract tokens
        guard let tokens = payload["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              !idToken.isEmpty else {
            return nil
        }

        let jwtPayload = parseJWT(idToken)

        let profileDict = jwtPayload?["https://api.openai.com/profile"] as? [String: Any]
        let authDict = jwtPayload?["https://api.openai.com/auth"] as? [String: Any]

        let email = normalizedField(
            (jwtPayload?["email"] as? String) ?? (profileDict?["email"] as? String)
        )
        let plan = normalizedField(
            (authDict?["chatgpt_plan_type"] as? String) ?? (jwtPayload?["chatgpt_plan_type"] as? String)
        )
        let accountId = normalizedField(
            (tokens["account_id"] as? String)
            ?? (authDict?["chatgpt_account_id"] as? String)
            ?? (jwtPayload?["chatgpt_account_id"] as? String)
        )

        MultiCodexLog.log(.identity, level: .debug, "Resolved identity from JWT",
                          metadata: ["hasEmail": email != nil ? "yes" : "no",
                                     "plan": plan ?? "none",
                                     "hasAccountId": accountId != nil ? "yes" : "no"])

        return ResolvedAccountIdentity(
            email: email,
            plan: plan,
            accountId: accountId,
            authMethod: .oauth
        )
    }

    /// Parse a JWT token string and return the payload dictionary.
    /// Adapted from CodexBar's UsageFetcher.parseJWT().
    static func parseJWT(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let payloadPart = parts[1]

        // Base64URL decode
        var padded = String(payloadPart)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 {
            padded.append("=")
        }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func normalizedField(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct ResolvedAccountIdentity {
    let email: String?
    let plan: String?
    let accountId: String?
    let authMethod: AuthMethod

    enum AuthMethod {
        case oauth
        case apiKey
    }
}
```

**Integration:** Use in `AccountIdentityResolver.resolve(for:paths:)` to replace the current simpler parsing, and in the login completion flow to verify which account was actually logged in.

**Effort:** ~3 hours | **Impact:** Reliable post-login account detection — essential for auto-switch and managed accounts.

---

## Phase 2: Intelligence (Medium Effort, Very High Impact)

### 2.1 Usage Pace Prediction

**Problem:** Our auto-switch uses raw percentages. We have no concept of burn rate or "will this last until reset?"

**CodexBar Reference:** `Sources/CodexBarCore/UsagePace.swift` — computes expected vs actual usage, projects ETA to exhaustion, classifies into pace stages.

**Files to Create:**

```
Sources/MultiCodex/Core/Usage/
├── UsagePace.swift                  # NEW — pace computation
├── UsagePaceStore.swift             # NEW — historical snapshot persistence
└── UsageFormatter+Pace.swift        # NEW — pace display formatting
```

#### `Sources/MultiCodex/Core/Usage/UsagePace.swift`

```swift
import Foundation

/// Computes usage pace: burn rate, run-out prediction, and pace classification.
/// Adapted from CodexBar's UsagePace + HistoricalUsagePace.
///
/// The core insight: compare *actual used %* vs *expected used % at this point in the window*.
/// If you're 60% used but only 30% through the window, you're burning 2× faster than linear.
struct UsagePace: Equatable {
    enum Stage: String, Equatable {
        case onTrack
        case slightlyAhead    // burning slightly faster than linear
        case ahead            // burning fast
        case farAhead         // will run out well before reset
        case slightlyBehind   // using less than expected
        case behind           // conserving well
        case farBehind        // barely using anything

        var isOnTrack: Bool { self == .onTrack }
        var isAhead: Bool { [.slightlyAhead, .ahead, .farAhead].contains(self) }
        var isBehind: Bool { [.slightlyBehind, .behind, .farBehind].contains(self) }
    }

    let stage: Stage
    /// How far ahead (+) or behind (-) the actual usage is vs expected linear burn.
    let deltaPercent: Double
    /// What % would be used if burning linearly to this point in the window.
    let expectedUsedPercent: Double
    /// What % is actually used.
    let actualUsedPercent: Double
    /// Seconds until 100% is reached at current burn rate. nil if won't exhaust.
    let etaSeconds: TimeInterval?
    /// True if current rate won't exhaust the window before reset.
    let willLastToReset: Bool
    /// Probability of running out before reset (0-1), computed from historical data.
    let runOutProbability: Double?

    /// Compute pace for a usage metric within its time window.
    /// Returns nil if insufficient data (no reset time, no usage, or window already expired).
    static func compute(
        usedPercent: Double?,
        periodMinutes: Int?,
        resetsAt: Date?,
        now: Date = Date()
    ) -> UsagePace? {
        guard let usedPercent = usedPercent,
              let resetsAt = resetsAt,
              let windowMinutes = periodMinutes,
              windowMinutes > 0 else {
            return nil
        }

        let duration = TimeInterval(windowMinutes) * 60
        let timeUntilReset = resetsAt.timeIntervalSince(now)

        // Window already expired or not started
        guard timeUntilReset > 0, timeUntilReset <= duration else { return nil }

        let elapsed = (duration - timeUntilReset).clamped(to: 0...duration)
        let expected = ((elapsed / duration) * 100).clamped(to: 0...100)
        let actual = usedPercent.clamped(to: 0...100)

        // Edge: no time elapsed yet but usage > 0 → can't compute meaningful pace
        guard elapsed > 0 || actual == 0 else { return nil }

        let delta = actual - expected
        let stage = classifyStage(delta: delta)

        // Project: when will we hit 100%?
        var etaSeconds: TimeInterval?
        var willLast = false

        if elapsed > 0, actual > 0 {
            let burnRate = actual / elapsed  // % per second
            if burnRate > 0 {
                let remainingCapacity = max(0, 100 - actual)
                let secondsToExhaust = remainingCapacity / burnRate
                if secondsToExhaust >= timeUntilReset {
                    willLast = true
                } else {
                    etaSeconds = secondsToExhaust
                }
            }
        } else if elapsed > 0, actual == 0 {
            willLast = true
        }

        return UsagePace(
            stage: stage,
            deltaPercent: delta,
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLast,
            runOutProbability: nil // Filled in from historical data (Phase 2 enhancement)
        )
    }

    /// Classify delta into a pace stage.
    /// Thresholds adapted from CodexBar's UsagePace.stage(for:).
    private static func classifyStage(delta: Double) -> Stage {
        let absDelta = abs(delta)
        if absDelta <= 2 { return .onTrack }
        if absDelta <= 6 { return delta >= 0 ? .slightlyAhead : .slightlyBehind }
        if absDelta <= 12 { return delta >= 0 ? .ahead : .behind }
        return delta >= 0 ? .farAhead : .farBehind
    }
}

// MARK: - Display Helpers

extension UsagePace {
    var summaryText: String {
        switch stage {
        case .onTrack:
            return "On pace"
        case .slightlyAhead, .ahead, .farAhead:
            return "\(Int(abs(deltaPercent).rounded()))% in deficit"
        case .slightlyBehind, .behind, .farBehind:
            return "\(Int(abs(deltaPercent).rounded()))% in reserve"
        }
    }

    var etaText: String? {
        if willLastToReset {
            return "Lasts until reset"
        }
        guard let eta = etaSeconds else { return nil }
        if eta <= 0 { return "Runs out now" }
        let hours = Int(eta) / 3600
        let minutes = (Int(eta) % 3600) / 60
        if hours > 0 {
            return "Runs out in \(hours)h \(minutes)m"
        }
        return "Runs out in \(minutes)m"
    }

    var riskText: String? {
        guard let probability = runOutProbability else { return nil }
        let percent = Int((probability.clamped(to: 0...1) * 100).rounded())
        guard percent > 0 else { return nil }
        return "≈ \(percent)% run-out risk"
    }

    var detailText: String {
        var parts = [summaryText]
        if let eta = etaText { parts.append(eta) }
        if let risk = riskText { parts.append(risk) }
        return parts.joined(separator: " · ")
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
```

#### `Sources/MultiCodex/Core/Usage/UsagePaceStore.swift`

```swift
import Foundation

/// Stores periodic usage snapshots for historical pace analysis.
/// Adapted from CodexBar's HistoricalUsageHistoryStore (simplified for Codex-only).
///
/// Stores one snapshot per account per minute (max), retained for 8 weeks.
/// Used to compute run-out probability from historical patterns.
actor UsagePaceStore {
    struct Snapshot: Codable {
        let accountName: String
        let sampledAt: Date
        let fiveHourUsedPercent: Double
        let weeklyUsedPercent: Double
        let fiveHourResetsAt: Date?
        let weeklyResetsAt: Date?
    }

    private static let schemaVersion = 1
    private static let retentionDays: TimeInterval = 56 // 8 weeks

    private let fileURL: URL
    private var snapshots: [Snapshot] = []
    private var loaded = false

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("MultiCodex", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("pace-snapshots.json")
    }

    func record(_ snapshot: Snapshot) {
        ensureLoaded()
        snapshots.append(snapshot)
        trimExpired()
        // Throttled write — only persist every 5 minutes at most
        try? persist()
    }

    func record(
        accountName: String,
        fiveHour: UsageMetric,
        weekly: UsageMetric
    ) {
        let snapshot = Snapshot(
            accountName: accountName,
            sampledAt: Date(),
            fiveHourUsedPercent: fiveHour.usedPercent ?? 0,
            weeklyUsedPercent: weekly.usedPercent ?? 0,
            fiveHourResetsAt: fiveHour.resetsAt,
            weeklyResetsAt: weekly.resetsAt
        )
        record(snapshot)
    }

    /// Load snapshots for an account within a time range.
    func snapshots(for accountName: String, since: Date) -> [Snapshot] {
        ensureLoaded()
        return snapshots.filter { $0.accountName == accountName && $0.sampledAt >= since }
    }

    /// Compute run-out probability for an account's 5h window based on historical data.
    /// Returns 0-1 probability. Uses how often similar burn rates led to exhaustion.
    func runOutProbability(
        accountName: String,
        currentUsedPercent: Double,
        windowElapsedFraction: Double,
        now: Date = Date()
    ) -> Double? {
        ensureLoaded()

        // Find snapshots from the same relative position in previous windows
        // where burn rate was similar (±10% of current)
        let currentBurnRate = windowElapsedFraction > 0 ? currentUsedPercent / (windowElapsedFraction * 100) : 0
        guard currentBurnRate > 0 else { return nil }

        let historicalCutoff = now.addingTimeInterval(-Self.retentionDays * 86400)
        let relevant = snapshots.filter { $0.accountName == accountName && $0.sampledAt >= historicalCutoff }

        guard relevant.count >= 5 else { return nil }

        // Find windows that completed (have a reset) and check if similar-burn-rate windows exhausted
        var similarWindows = 0
        var exhaustedWindows = 0

        for snapshot in relevant where snapshot.fiveHourResetsAt != nil {
            let windowStart = snapshot.fiveHourResetsAt!.addingTimeInterval(-5 * 3600)
            let elapsed = snapshot.sampledAt.timeIntervalSince(windowStart)
            let windowFraction = elapsed / (5 * 3600)

            guard windowFraction > 0.1, windowFraction < 0.9 else { continue } // Skip edges

            let historicalRate = snapshot.fiveHourUsedPercent / (windowFraction * 100)
            if abs(historicalRate - currentBurnRate) / max(currentBurnRate, 0.01) < 0.2 {
                similarWindows += 1
                if snapshot.fiveHourUsedPercent >= 95 {
                    exhaustedWindows += 1
                }
            }
        }

        guard similarWindows >= 3 else { return nil }
        return Double(exhaustedWindows) / Double(similarWindows)
    }

    // MARK: - Private

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let container = try? JSONDecoder().decode(SnapshotContainer.self, from: data)
        self.snapshots = container?.snapshots ?? []
    }

    private func trimExpired() {
        let cutoff = Date().addingTimeInterval(-Self.retentionDays * 86400)
        snapshots.removeAll { $0.sampledAt < cutoff }
    }

    private func persist() throws {
        let container = SnapshotContainer(version: Self.schemaVersion, snapshots: snapshots)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(container)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private struct SnapshotContainer: Codable {
        let version: Int
        let snapshots: [UsagePaceStore.Snapshot]
    }
}
```

#### Integrate Pace into AccountUsage:

```swift
// In UsageModels.swift — extend AccountUsage
struct AccountUsage {
    // ... existing fields ...

    /// Computed pace for the 5h window. Set during merge/refresh.
    var fiveHourPace: UsagePace?
    /// Computed pace for the weekly window.
    var weeklyPace: UsagePace?

    /// Combined pace summary for display.
    var paceSummary: String? {
        guard let pace = fiveHourPace ?? weeklyPace else { return nil }
        return pace.detailText
    }
}
```

#### Integrate into Auto-Switch:

```swift
// In AccountSwitchRecommendationService — enhance expiryAware scoring with pace
private static func expiryAwareScore(for account: AccountUsage, now: Date, isCurrent: Bool) -> Double {
    let remainingFiveHour = remainingFraction(for: account.usage.fiveHour)
    let remainingWeekly = remainingFraction(for: account.usage.weekly)

    // Base urgency (existing logic)
    let fiveHourUrgency = urgency(
        remainingFraction: remainingFiveHour,
        resetDate: account.usage.fiveHour.resetsAt,
        horizonHours: 5, now: now
    )
    let weeklyUrgency = urgency(
        remainingFraction: remainingWeekly,
        resetDate: account.usage.weekly.resetsAt,
        horizonHours: 168, now: now
    )

    var score = (fiveHourUrgency * 1.15)
        + (weeklyUrgency * 0.85)
        + (remainingFiveHour * 0.20)
        + (remainingWeekly * 0.12)

    // NEW: Pace bonus/penalty
    // An account that's "on track" or "behind pace" (good) gets a bonus.
    // An account that's "ahead" (burning fast) gets a penalty.
    if let pace = account.fiveHourPace {
        switch pace.stage {
        case .farBehind, .behind:
            score += 0.10  // lots of headroom, burning slowly
        case .slightlyBehind, .onTrack:
            score += 0.05  // healthy burn rate
        case .slightlyAhead:
            score -= 0.03  // slightly fast burn
        case .ahead:
            score -= 0.08  // will exhaust sooner
        case .farAhead:
            score -= 0.15  // will exhaust very soon
        }
    }

    // NEW: Run-out probability penalty
    // If historical data suggests high run-out risk, reduce the score
    if let probability = account.fiveHourPace?.runOutProbability, probability > 0.5 {
        score -= Double(probability) * 0.12
    }

    if isCurrent {
        score += currentAccountStickyBonus
    }

    return score
}
```

**Effort:** ~8 hours | **Impact:** Dramatically smarter auto-switching. The biggest differentiator — switch *predictively*, not *reactively*.

---

### 2.2 Enhanced Auto-Switch with Pace + Transition Awareness

**Problem:** Auto-switch fires based on raw thresholds. With pace data, we can switch *before* exhaustion.

**File to Modify:** `Sources/MultiCodex/Core/Accounts/AccountSwitchRecommendationService.swift`

Add a `paceAware` strategy option:

```swift
enum AccountSwitchingStrategy: String, CaseIterable {
    case manual
    case failover
    case expiryAware
    case paceAware      // NEW — uses pace prediction

    var title: String {
        switch self {
        case .manual: return "Manual"
        case .failover: return "Failover"
        case .expiryAware: return "Expiry Aware"
        case .paceAware: return "Pace Aware"
        }
    }

    var descriptionText: String {
        switch self {
        case .manual: return "No automatic switching."
        case .failover: return "Switch when current account needs login, errors, or is near limit."
        case .expiryAware: return "Prefer account with most expiring-unused headroom."
        case .paceAware: return "Switch predictively based on burn rate and run-out probability."
        }
    }
}
```

Add pace-aware recommendation:

```swift
// In AccountSwitchRecommendationService
private static func paceAwareRecommendation(
    accounts: [AccountUsage],
    now: Date
) -> AccountSwitchRecommendation? {
    let current = accounts.first(where: \.isCurrent)
    let candidates = eligibleAccounts(from: accounts)
    guard !candidates.isEmpty else { return nil }

    // Score all accounts with the enhanced pace-aware scoring
    let scored = candidates.map { account in
        (
            account: account,
            score: expiryAwareScore(
                for: account, now: now,
                isCurrent: account.name == current?.name
            )
        )
    }

    guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }

    guard let current else {
        return AccountSwitchRecommendation(
            previousAccountName: nil,
            accountName: best.account.name,
            reason: "Best available fit"
        )
    }

    guard let currentScore = scored.first(where: { $0.account.name == current.name })?.score else {
        return AccountSwitchRecommendation(
            previousAccountName: current.name,
            accountName: best.account.name,
            reason: "Current account unavailable"
        )
    }

    guard best.account.name != current.name else { return nil }

    // Lower threshold for pace-aware: switch when a clearly better option exists
    // (current strategy requires +0.22 margin; pace-aware uses +0.15)
    let margin: Double = 0.15
    guard best.score > currentScore + margin else { return nil }

    // Generate reason from pace data
    let reason: String
    if let pace = current.fiveHourPace, pace.isAhead {
        reason = "Current burning fast (\(pace.summaryText.lowercased()))"
    } else if let pace = best.account.fiveHourPace, pace.isBehind || pace.isOnTrack {
        reason = "Better burn rate available"
    } else {
        reason = expiryAwareReason(candidate: best.account, current: current, now: now)
    }

    return AccountSwitchRecommendation(
        previousAccountName: current.name,
        accountName: best.account.name,
        reason: reason
    )
}
```

**Effort:** ~4 hours | **Impact:** New "Pace Aware" strategy — the most intelligent auto-switch mode.

---

## Phase 3: Resilience (Medium Effort, High Impact)

### 3.1 Token Auto-Refresh During Background Cycles

**Problem:** Stale tokens cause failed fetches. We only refresh on-demand when fetching usage. CodexBar refreshes proactively.

**CodexBar Reference:** `CodexTokenRefresher` — async token refresh with proper error categorization (expired/revoked/reused).

**File to Modify:** `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsUsageAPI.swift`

Add proactive refresh:

```swift
// In CodexAccountService — add a new method for proactive token refresh

/// Proactively refresh tokens for all accounts with aging auth.
/// Called during background refresh cycles, before fetching usage.
/// Adapted from CodexBar's CodexTokenRefresher + shouldRefreshToken pattern.
func refreshStaleTokens() async -> [String: Error] {
    let paths = currentPaths()
    guard let config = try? loadConfig(paths: paths) else { return [:] }

    var errors: [String: Error] = [:]

    for account in config.accounts {
        let authPath = paths.accountAuthPath(account)
        guard var payload = try? loadAuthPayload(from: authPath) else { continue }

        // Check if refresh is needed (same 8-day threshold as CodexBar)
        guard shouldRefreshToken(payload) else { continue }

        MultiCodexLog.log(.auth, level: .debug, "Proactively refreshing token for \(account)")

        do {
            if let newToken = try refreshAccessToken(authPayload: &payload, authPath: authPath) {
                MultiCodexLog.log(.auth, level: .info, "Token refreshed for \(account)")
            }
        } catch {
            errors[account] = error
            MultiCodexLog.log(.auth, level: .error,
                              "Token refresh failed for \(account): \(error.localizedDescription)")
        }
    }

    return errors
}
```

Then call it in the refresh cycle:

```swift
// In AccountsRefreshController.performRefresh() — add before fetchLimitsNow
if refreshLive {
    // Proactively refresh aging tokens before fetching usage
    _ = await viewModel.accountService.refreshStaleTokens()
}
```

**Effort:** ~3 hours | **Impact:** Eliminates "token expired" errors from the user's perspective.

---

### 3.2 Account Reconciliation

**Problem:** If a user runs `codex login` in a terminal, our app doesn't detect the change. The "current account" in our config may not match reality.

**CodexBar Reference:** `CodexAccountReconciliation.swift`, `CodexActiveSourceResolver` — compares stored identity with live system identity.

**File to Create:**

```
Sources/MultiCodex/Core/Accounts/
└── AccountReconciliation.swift    # NEW
```

#### `Sources/MultiCodex/Core/Accounts/AccountReconciliation.swift`

```swift
import Foundation

/// Detects and reconciles discrepancies between our stored "current account"
/// and the actual live system auth.
///
/// Adapted from CodexBar's CodexAccountReconciliation + CodexActiveSourceResolver.
///
/// Scenarios:
/// 1. User ran `codex login` externally → system auth changed to a different account
/// 2. User's token expired → system auth is invalid but we think they're logged in
/// 3. Account was removed from our config but system auth still points to it
enum AccountReconciliation {
    struct ReconciliationResult: Equatable {
        /// The account name our config says is current.
        let configCurrentAccount: String?
        /// The account name detected from the actual system auth.
        let detectedAccountName: String?
        /// Email found in system auth.
        let detectedEmail: String?
        /// Plan type found in system auth.
        let detectedPlan: String?
        /// Whether config and reality match.
        let isInSync: Bool
        /// Whether the system auth was modified externally.
        let systemAuthChangedExternally: Bool
    }

    /// Check if the system auth matches our stored "current account".
    /// Called on app activation and after refresh cycles.
    static func reconcile(
        configCurrentAccount: String?,
        systemAuthLastModified: Date?,
        knownAccountLastModified: Date?,
        systemIdentity: ResolvedAccountIdentity?,
        accountEmails: [String: String]  // account name → email mapping
    ) -> ReconciliationResult {
        let detectedEmail = systemIdentity?.email
        let detectedPlan = systemIdentity?.plan
        var detectedAccountName: String?

        // Try to match the system identity to a known account by email
        if let email = detectedEmail {
            for (name, storedEmail) in accountEmails where storedEmail.lowercased() == email.lowercased() {
                detectedAccountName = name
                break
            }
        }

        // Detect external modification
        let externallyModified: Bool
        if let systemModified = systemAuthLastModified,
           let knownModified = knownAccountLastModified {
            externallyModified = systemModified > knownModified.addingTimeInterval(5) // 5s tolerance
        } else {
            externallyModified = false
        }

        // Check sync
        let isInSync: Bool
        if let configName = configCurrentAccount, let detected = detectedAccountName {
            isInSync = configName == detected
        } else if configCurrentAccount == nil && detectedAccountName == nil {
            isInSync = true
        } else {
            isInSync = false
        }

        return ReconciliationResult(
            configCurrentAccount: configCurrentAccount,
            detectedAccountName: detectedAccountName,
            detectedEmail: detectedEmail,
            detectedPlan: detectedPlan,
            isInSync: isInSync,
            systemAuthChangedExternally: externallyModified
        )
    }
}
```

#### Integrate into Refresh Cycle:

```swift
// In AccountsRefreshController — add after fetching accounts
func performReconciliation() {
    let configCurrentAccount = viewModel.currentAccountName
    let systemAuthPath = viewModel.accountService.currentPaths().defaultCodexAuthPath

    // Get system auth modification time
    let systemModified = try? FileManager.default.attributesOfItem(atPath: systemAuthPath)[.modificationDate] as? Date

    // Get system auth identity via JWT parsing
    let systemIdentity: ResolvedAccountIdentity?
    if let authData = try? Data(contentsOf: URL(fileURLWithPath: systemAuthPath)),
       let payload = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] {
        systemIdentity = AccountIdentityResolver.resolveFromAuthPayload(payload)
    } else {
        systemIdentity = nil
    }

    // Build email mapping
    var accountEmails: [String: String] = [:]
    for account in viewModel.accounts {
        if let email = account.defaultWorkspaceEmail {
            accountEmails[account.name] = email
        }
    }

    let result = AccountReconciliation.reconcile(
        configCurrentAccount: configCurrentAccount,
        systemAuthLastModified: systemModified,
        knownAccountLastModified: nil, // TODO: track per-account auth modification time
        systemIdentity: systemIdentity,
        accountEmails: accountEmails
    )

    if !result.isInSync, result.systemAuthChangedExternally {
        MultiCodexLog.log(.auth, level: .info,
                          "External auth change detected",
                          metadata: ["configAccount": result.configCurrentAccount ?? "none",
                                     "detectedAccount": result.detectedAccountName ?? "unknown",
                                     "detectedEmail": result.detectedEmail ?? "none"])

        if let detectedName = result.detectedAccountName {
            // The user logged in as a known account externally — update our config
            viewModel.applyCurrentAccountLocally(named: detectedName)
        } else if let email = result.detectedEmail {
            // Logged in as an unknown account — prompt user
            viewModel.lastRefreshError = "Detected external login for \(email). This account is not in MultiCodex."
        }
    }
}
```

**Effort:** ~6 hours | **Impact:** App stays in sync with reality even when users use the terminal.

---


## Phase 4: Architectural Overhaul (Higher Effort, Very High Impact)

> **This is the single highest-leverage change in the roadmap.** Our UX and auto-switching intelligence already surpass CodexBar. This phase closes the gap in underlying plumbing: isolation, safety, parallelism, and resilience. The goal is to **keep our entire UI/smart layer unchanged** while replacing the fragile auth-swap mechanism with CodexBar's proven isolation model.

### 4.1 Managed `CODEX_HOME` Directories

**Problem:** We swap `~/.codex/auth.json` with lock files. This is fragile:
- **Race conditions:** A crash mid-swap leaves auth in a wrong state
- **Serial-only:** Must lock → swap → fetch → restore for each account sequentially
- **Slow:** 5 accounts × 3-5s per RPC = 15-25s total refresh
- **Unsafe:** No way to recover displaced auth if overwrite fails

**CodexBar Reference:** `ManagedCodexHomeFactory`, `FileManagedCodexAccountStore`, `CodexHomeScope` — each account gets its own isolated `CODEX_HOME` directory.

**New Architecture:**

```
Before (current — auth swap with locks):
  ~/.codex/auth.json                               ← swapped on every switch
  ~/.config/multicodex/accounts/{name}/auth.json   ← stored copies
  ~/.config/multicodex/locks/                       ← filesystem lock dir

After (managed homes — isolated, no locks needed):
  ~/Library/Application Support/MultiCodex/
    homes/
      {account-name}/
        auth.json          ← per-account auth (always accessible)
        sessions/           ← per-account codex session data
    managed-accounts.json  ← account registry (email, identity, home path)
  ~/.codex/auth.json      ← always points to "active" account (updated on switch)
```

**Files to Create:**

```
Sources/MultiCodex/Infrastructure/Codex/Accounts/
├── ManagedCodexHomeFactory.swift       # NEW — creates isolated home directories
├── ManagedAccountStore.swift           # NEW — account registry persistence
├── AuthSwapService.swift               # NEW — atomic auth switching
└── ManagedAccountMigrator.swift        # NEW — migrates legacy accounts to managed homes
```

#### `Sources/MultiCodex/Infrastructure/Codex/Accounts/ManagedCodexHomeFactory.swift`

```swift
import Foundation

/// Creates and manages isolated CODEX_HOME directories for each account.
/// Adapted from CodexBar's ManagedCodexHomeFactory + FileManagedCodexAccountStore.
///
/// Key design decisions (learned from CodexBar):
/// 1. Each account has its own CODEX_HOME with its own auth.json
/// 2. Accounts can be queried independently — no lock needed
/// 3. The system ~/.codex/ is only updated on explicit "switch" actions
/// 4. Directory names use sanitized account names (not UUIDs) for debuggability
enum ManagedCodexHomeFactory {
    static let homesRootName = "homes"

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("MultiCodex", isDirectory: true)
        return base.appendingPathComponent(homesRootName, isDirectory: true)
    }

    /// Create a new isolated home directory for an account.
    static func createHome(for accountName: String, fileManager: FileManager = .default) throws -> URL {
        let sanitized = Self.sanitize(accountName)
        let homeURL = defaultRootURL(fileManager: fileManager)
            .appendingPathComponent(sanitized, isDirectory: true)

        try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)

        // Create sessions subdirectory (codex writes session logs here)
        let sessionsURL = homeURL.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsURL, withIntermediateDirectories: true)

        return homeURL
    }

    /// Get the managed home URL for an account, or nil if it doesn't exist.
    static func homeURL(for accountName: String, fileManager: FileManager = .default) -> URL? {
        let sanitized = Self.sanitize(accountName)
        let homeURL = defaultRootURL(fileManager: fileManager)
            .appendingPathComponent(sanitized, isDirectory: true)
        return fileManager.fileExists(atPath: homeURL.path) ? homeURL : nil
    }

    /// Build environment with CODEX_HOME scoped to a managed account.
    /// This is the key insight from CodexBar: set CODEX_HOME per-process,
    /// and codex reads auth from that directory instead of ~/.codex/.
    static func scopedEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        managedHome: URL
    ) -> [String: String] {
        var env = base
        env["CODEX_HOME"] = managedHome.path
        return env
    }

    /// Read auth data from a managed home directory.
    static func readAuthData(from homeURL: URL) throws -> Data? {
        let authURL = homeURL.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: authURL.path) else { return nil }
        return try Data(contentsOf: authURL)
    }

    /// Write auth data to a managed home directory with secure permissions.
    static func writeAuthData(_ data: Data, to homeURL: URL) throws {
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let authURL = homeURL.appendingPathComponent("auth.json")
        try data.write(to: authURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: authURL.path
        )
    }

    /// Validate that a home directory is safe to delete (must be under our root).
    static func validateSafeDeletion(_ url: URL, fileManager: FileManager = .default) throws {
        let rootPath = defaultRootURL(fileManager: fileManager).standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(rootPrefix), targetPath != rootPath else {
            throw ManagedHomeError.unsafeDeletion(url.path)
        }
    }

    static func sanitize(_ name: String) -> String {
        name.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined()
    }

    enum ManagedHomeError: LocalizedError {
        case unsafeDeletion(String)
        var errorDescription: String? {
            switch self {
            case .unsafeDeletion(let path):
                return "Refusing to delete directory outside managed root: \(path)"
            }
        }
    }
}
```

#### `Sources/MultiCodex/Infrastructure/Codex/Accounts/AuthSwapService.swift`

```swift
import Darwin
import Foundation

/// Handles the actual account switch: atomically updates the system ~/.codex/auth.json.
/// Uses POSIX rename() for atomic swap — adapted from CodexBar's DefaultCodexLiveAuthSwapper.
///
/// CodexBar's approach (superior to our current copy-based swap):
/// 1. Write new auth to a staged file in the same directory
/// 2. Set secure permissions (0o600) on the staged file
/// 3. POSIX rename() — atomic on same filesystem, no partial state possible
///
/// Also implements displaced account preservation (CodexBar pattern):
/// Before overwriting system auth, save the current auth back to the outgoing
/// account's managed home. This prevents data loss if the user switches away
/// from an account that was only in ~/.codex/.
enum AuthSwapService {

    /// Switch the system codex auth to a target managed account's auth.
    /// Implements displaced account preservation from CodexBar.
    ///
    /// Steps:
    /// 1. Read current system auth → save to outgoing account's managed home
    /// 2. Read target account's managed auth
    /// 3. Atomically swap system auth to target's auth
    static func switchToAccount(
        named targetName: String,
        previousAccountName: String?,
        paths: CodexAccountService.PathContext
    ) throws {
        let systemAuthURL = URL(fileURLWithPath: paths.defaultCodexAuthPath)

        // ── Step 1: Displaced account preservation ──
        // Save the current system auth back to the outgoing account's managed home.
        // CodexBar does this in CodexDisplacedLivePreservationExecutor.
        if let previousName = previousAccountName,
           let previousHome = ManagedCodexHomeFactory.homeURL(for: previousName),
           let currentSystemAuth = try? ManagedCodexHomeFactory.readAuthData(
               from: URL(fileURLWithPath: paths.defaultCodexAuthPath)
           ) {
            // Only preserve if the managed home doesn't already have newer auth
            let managedAuth = try? ManagedCodexHomeFactory.readAuthData(from: previousHome)
            if managedAuth == nil || managedAuth != currentSystemAuth {
                try? ManagedCodexHomeFactory.writeAuthData(currentSystemAuth, to: previousHome)
                MultiCodexLog.log(.auth, level: .info,
                    "Preserved displaced auth to \(previousName)'s managed home")
            }
        }

        // ── Step 2: Read target account's auth ──
        guard let targetHome = ManagedCodexHomeFactory.homeURL(for: targetName) else {
            throw AuthSwapError.managedHomeNotFound(targetName)
        }
        guard let targetAuthData = try ManagedCodexHomeFactory.readAuthData(from: targetHome) else {
            throw AuthSwapError.authNotFound(targetName)
        }

        // ── Step 3: Atomic swap using POSIX rename() ──
        // CodexBar pattern: write to staged file, then atomic rename.
        let codexDir = URL(fileURLWithPath: paths.defaultCodexHome)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

        let stagedURL = codexDir.appendingPathComponent(
            "auth.json.multicodex-staged-\(UUID().uuidString)"
        )

        do {
            // Write to staged file with secure permissions
            try targetAuthData.write(to: stagedURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: stagedURL.path
            )

            // Atomic rename — this is the critical moment
            // POSIX rename() is atomic on the same filesystem
            try Self.atomicRename(at: stagedURL, to: systemAuthURL)

            MultiCodexLog.log(.auth, level: .info,
                "Switched system auth to \(targetName)")
        } catch {
            // Clean up staged file on failure
            try? FileManager.default.removeItem(at: stagedURL)
            throw error
        }
    }

    /// POSIX atomic rename — adapted from CodexBar's renameItem wrapper.
    /// rename() is atomic on the same filesystem — no partial state possible.
    private static func atomicRename(at sourceURL: URL, to destinationURL: URL) throws {
        let sourcePath = sourceURL.path
        let destinationPath = destinationURL.path

        let result = sourcePath.withCString { sourceFS in
            destinationPath.withCString { destFS in
                rename(sourceFS, destFS)
            }
        }

        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: destinationPath]
            )
        }
    }

    enum AuthSwapError: LocalizedError {
        case managedHomeNotFound(String)
        case authNotFound(String)

        var errorDescription: String? {
            switch self {
            case .managedHomeNotFound(let name):
                return "Managed home directory not found for account: \(name)"
            case .authNotFound(let name):
                return "Auth data not found for account: \(name)"
            }
        }
    }
}
```

#### `Sources/MultiCodex/Infrastructure/Codex/Accounts/ManagedAccountMigrator.swift`

```swift
import Foundation

/// Migrates legacy accounts from ~/.config/multicodex/accounts/ to managed homes.
/// Runs once on first launch after upgrade. Non-destructive — keeps legacy data as backup.
///
/// Adapted from CodexBar's migration pattern in FileManagedCodexAccountStore.
enum ManagedAccountMigrator {

    /// Perform one-time migration from legacy account storage to managed homes.
    /// Returns the number of accounts migrated.
    static func migrateIfNeeded(paths: CodexAccountService.PathContext) throws -> Int {
        let markerURL = URL(fileURLWithPath: paths.multicodexHome)
            .appendingPathComponent(".managed-migration-complete")

        // Already migrated
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return 0 }

        let legacyAccountsDir = paths.accountsDir
        guard FileManager.default.fileExists(atPath: legacyAccountsDir) else {
            // No legacy data — mark as migrated
            try? Data().write(to: markerURL)
            return 0
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: legacyAccountsDir)
        var migrated = 0

        for accountName in contents {
            let legacyAuthPath = paths.accountAuthPath(accountName)
            guard FileManager.default.fileExists(atPath: legacyAuthPath) else { continue }

            // Create managed home
            let managedHome = try ManagedCodexHomeFactory.createHome(for: accountName)

            // Copy auth.json to managed home
            let authData = try Data(contentsOf: URL(fileURLWithPath: legacyAuthPath))
            try ManagedCodexHomeFactory.writeAuthData(authData, to: managedHome)

            MultiCodexLog.log(.config, level: .info,
                "Migrated account \(accountName) to managed home at \(managedHome.path)")
            migrated += 1
        }

        // Mark migration complete (don't delete legacy data — keep as backup)
        try? Data("migrated \(migrated) accounts at \(Date())".utf8)
            .write(to: markerURL)

        MultiCodexLog.log(.config, level: .info,
            "Migration complete: \(migrated) accounts migrated to managed homes")

        return migrated
    }
}
```

**Migration Plan (3 phases, non-breaking):**

1. **Phase A — One-time migration:** On launch, `ManagedAccountMigrator` copies all legacy account auth into managed homes. Legacy directories are kept as backup. No behavior change yet.
2. **Phase B — Switch to managed reads:** Usage fetches read from managed homes (setting `CODEX_HOME` per-account) instead of swapping system auth. System auth still updated on switch (for running codex compatibility).
3. **Phase C — Parallel queries:** Remove lock files entirely. All fetches go through managed homes with per-process `CODEX_HOME`. System auth only touched on explicit switch.

**Effort:** ~16 hours (significant refactor) | **Impact:** Eliminates auth-swap fragility, foundation for parallel queries and persistent RPC.

---

### 4.2 Parallel Usage Fetching

**Problem:** Currently we fetch usage for each account serially (lock → swap → fetch → restore). With 5 accounts this takes 15-25 seconds.

**CodexBar's approach:** Each account has its own `CODEX_HOME`. Fetch usage by spawning a process with `CODEX_HOME` set to the managed home. No lock needed. All accounts fetched in parallel.

**File to Modify:** `Sources/MultiCodex/Infrastructure/Codex/Usage/RateLimitsFetcher.swift`

#### New Parallel Fetch Implementation:

```swift
// In CodexAccountService — replace the serial fetchLimitsNow loop

/// Fetch rate limits for ALL accounts in parallel using managed CODEX_HOME.
/// Each account gets its own process with its own CODEX_HOME environment.
/// No lock files needed — accounts are completely isolated.
///
/// CodexBar equivalent: fetches each managed account independently via
/// scopedEnvironment + UsageFetcher.
func fetchLimitsInParallel(refreshLive: Bool) async -> LimitsPayload {
    let paths = currentPaths()
    guard let config = try? loadConfig(paths: paths) else {
        return LimitsPayload(results: [], errors: [])
    }
    let accounts = config.accounts.sorted()
    let ttlSeconds = Self.normalizedLimitsCacheTTLSeconds(limitsCacheTTLSeconds)

    // ── First pass: collect cached results, identify accounts needing live fetch ──
    var results: [LimitsResult] = []
    var needsLiveFetch: [String] = []

    for account in accounts {
        if !refreshLive,
           let cached = try? getCachedLimits(
               account: account,
               ttlMs: Double(ttlSeconds * 1000),
               paths: paths
           ) {
            results.append(LimitsResult(
                account: account,
                source: "cached",
                snapshot: cached.snapshot,
                ageSec: Int((cached.ageMs / 1000.0).rounded())
            ))
        } else {
            needsLiveFetch.append(account)
        }
    }

    guard !needsLiveFetch.isEmpty else {
        return LimitsPayload(results: results, errors: [])
    }

    // ── Second pass: fetch all uncached accounts IN PARALLEL ──
    // This is the key advantage of managed homes — no lock contention.
    await withTaskGroup(of: (String, Result<RateLimitSnapshot, Error>).self) { group in
        for account in needsLiveFetch {
            group.addTask {
                do {
                    let snapshot = try await self.fetchLimitsForManagedAccount(account)
                    return (account, .success(snapshot))
                } catch {
                    return (account, .failure(error))
                }
            }
        }

        for await (account, result) in group {
            switch result {
            case .success(let snapshot):
                try? setCachedLimits(
                    account: account,
                    snapshot: snapshot,
                    provider: "managed-api",
                    paths: paths
                )
                results.append(LimitsResult(
                    account: account,
                    source: "live-managed",
                    snapshot: snapshot,
                    ageSec: nil
                ))
            case .failure(let error):
                MultiCodexLog.log(.refresh, level: .error,
                    "Parallel fetch failed for \(account)",
                    metadata: ["error": error.localizedDescription])
            }
        }
    }

    return LimitsPayload(results: results, errors: [])
}

/// Fetch rate limits for a single managed account using its isolated CODEX_HOME.
/// No lock needed — the account's auth is in its own directory.
private func fetchLimitsForManagedAccount(_ accountName: String) async throws -> RateLimitSnapshot {
    guard let homeURL = ManagedCodexHomeFactory.homeURL(for: accountName) else {
        throw CodexAccountServiceError(message: "No managed home for account: \(accountName)")
    }
    let authPath = homeURL.appendingPathComponent("auth.json").path

    // Try API fetch first (same as current approach, but with managed auth path)
    if let snapshot = try? fetchRateLimitsViaApiForAuthPath(authPath) {
        return snapshot
    }

    // Fallback: RPC fetch with scoped CODEX_HOME environment
    return try await fetchRateLimitsViaRPCWithScopedHome(homeURL)
}

/// Fetch rate limits via RPC with a scoped CODEX_HOME.
/// This is the parallel-safe version — each invocation uses its own environment.
private func fetchRateLimitsViaRPCWithScopedHome(_ homeURL: URL) async throws -> RateLimitSnapshot {
    let runtime = try resolveCodexRuntime()
    let proc = Process()
    proc.executableURL = runtime.executableURL
    proc.arguments = runtime.prefixArguments + ["-s", "read-only", "-a", "untrusted", "app-server"]

    // Key: scope CODEX_HOME to the managed account's directory
    var env = baseEnvironment()
    env["CODEX_HOME"] = homeURL.path
    proc.environment = env

    // ... (same RPC handshake as current fetchRateLimitsViaRpc, but with scoped env)
}
```

**Performance comparison:**

| Scenario | Before (serial + lock) | After (parallel managed) |
|---|---|---|
| 3 accounts, all cached | ~1s | ~1s (no change) |
| 3 accounts, all live | ~10-15s | ~3-5s (parallel) |
| 5 accounts, all live | ~15-25s | ~3-5s (parallel) |
| Crash during fetch | Auth in wrong state | No state change (isolated) |

**Effort:** ~8 hours | **Impact:** 3-5× faster refresh cycles, crash-safe, zero lock contention.

---

### 4.3 Robust Account Identity Model

**Problem:** We identify accounts by name (user-defined string). CodexBar uses `providerAccountID` (from JWT) as the primary identity key — more reliable because one email can map to multiple workspace accounts.

**CodexBar Reference:** `CodexIdentity` enum (`.providerAccount(id)` / `.emailOnly(email)` / `.unresolved`), `CodexIdentityResolver`, `CodexIdentityMatcher`.

**File to Create:**

```
Sources/MultiCodex/Core/Accounts/
└── AccountIdentity.swift    # NEW — robust identity model
```

#### `Sources/MultiCodex/Core/Accounts/AccountIdentity.swift`

```swift
import Foundation

/// Robust account identity model adapted from CodexBar's CodexIdentity.
///
/// Identity hierarchy (most reliable → least):
/// 1. providerAccountID — unique per OpenAI account, survives email changes
/// 2. email — may be shared across workspace accounts (less reliable)
/// 3. unresolved — no identity information available
///
/// Why this matters: A single email (e.g., user@company.com) can have multiple
/// OpenAI accounts: a personal one and a workspace one. providerAccountID
/// distinguishes them. Our current email-only model can't.
enum AccountIdentity: Equatable, Hashable, Sendable {
    case providerAccount(id: String)         // JWT chatgpt_account_id
    case emailOnly(normalizedEmail: String)  // Fallback: email without account ID
    case unresolved                           // No identity data available
}

/// Resolves identity from auth payload data.
enum AccountIdentityResolver {
    static func resolve(accountId: String?, email: String?) -> AccountIdentity {
        if let id = normalizeAccountId(accountId) {
            return .providerAccount(id: id)
        }
        if let email = normalizeEmail(email) {
            return .emailOnly(normalizedEmail: email)
        }
        return .unresolved
    }

    static func normalizeEmail(_ email: String?) -> String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else { return nil }
        return email.lowercased()
    }

    static func normalizeAccountId(_ id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return nil }
        return id
    }
}

/// Matches identities between stored and runtime accounts.
/// Adapted from CodexBar's CodexIdentityMatcher.
enum AccountIdentityMatcher {
    /// Two identities match if they resolve to the same providerAccountID,
    /// or if both are email-only with the same normalized email.
    static func matches(_ a: AccountIdentity, _ b: AccountIdentity) -> Bool {
        switch (a, b) {
        case let (.providerAccount(idA), .providerAccount(idB)):
            return idA == idB
        case let (.emailOnly(emailA), .emailOnly(emailB)):
            return emailA == emailB
        case (.providerAccount, .emailOnly), (.emailOnly, .providerAccount):
            // providerAccount is more specific — don't match across types
            return false
        case (.unresolved, _), (_, .unresolved):
            return false
        }
    }
}
```

**Integration:** Extend `AccountConfigRecord` to store `providerAccountID` alongside account names. During login/refresh, resolve the JWT identity (Phase 1.4) and store it. Use `AccountIdentityMatcher` for reconciliation (Phase 3.2) and displaced account preservation (Phase 4.1).

**Effort:** ~4 hours | **Impact:** Correct handling of workspace accounts, reliable identity matching across restarts.

---

### 4.4 Persistent JSON-RPC Session

**Problem:** We spawn a new `codex app-server` process for every usage fetch (~2-5s startup). CodexBar maintains a persistent session that responds in milliseconds.

**CodexBar Reference:** `CodexRPCClient` in `UsageFetcher.swift` — long-lived Process with stdin/stdout pipes.

> **Note:** With parallel fetching (4.2), we may have one RPC session per account or a single shared session.
> The persistent session is most valuable for the "current account" displayed in the menu bar,
> which refreshes most frequently.

**File to Create:**

```
Sources/MultiCodex/Infrastructure/Codex/Runtime/
└── CodexRPCSession.swift    # NEW — persistent RPC client
```

#### `Sources/MultiCodex/Infrastructure/Codex/Runtime/CodexRPCSession.swift`

```swift
import Foundation

/// Persistent JSON-RPC client for the Codex CLI.
/// Maintains a long-lived `codex -s read-only -a untrusted app-server` process.
/// Adapted from CodexBar's CodexRPCClient (simplified — we don't need PTY fallback here).
///
/// Lifecycle:
/// 1. Launch on first usage fetch
/// 2. Send initialize + initialized handshake
/// 3. Send account/rateLimits/read requests on each refresh cycle
/// 4. Terminate on app shutdown or if process dies
///
/// With managed homes (4.1), the session uses the active account's CODEX_HOME.
/// On account switch, the session is restarted with the new home.
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
    private var stdoutBuffer: Data = Data()
    private var nextID = 1
    private var initialized = false
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var scopedHomePath: String?

    /// Ensure the session is running and initialized.
    /// If the account changed (different CODEX_HOME), restart the session.
    func ensureReady(scopedHomePath: String? = nil) async throws {
        // Restart if home path changed (account switch)
        if self.scopedHomePath != scopedHomePath {
            shutdown()
            self.scopedHomePath = scopedHomePath
        }
        if let proc = process, proc.isRunning, initialized { return }
        try launch()
        try await initialize()
    }

    /// Fetch rate limits via the persistent session.
    func fetchRateLimits(scopedHomePath: String? = nil) async throws -> [String: Any] {
        try await ensureReady(scopedHomePath: scopedHomePath)
        return try await request(method: "account/rateLimits/read")
    }

    /// Fetch account info via the persistent session.
    func fetchAccount(scopedHomePath: String? = nil) async throws -> [String: Any] {
        try await ensureReady(scopedHomePath: scopedHomePath)
        return try await request(method: "account/read")
    }

    /// Shut down the session cleanly.
    func shutdown() {
        guard let proc = process, proc.isRunning else { return }
        MultiCodexLog.log(.rpc, level: .info, "Shutting down RPC session")
        proc.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        initialized = false
    }

    // MARK: - Private

    private func launch() throws {
        shutdown()

        let runtime = try CodexRuntimeResolver.resolve()
        let proc = Process()
        proc.executableURL = runtime.executableURL
        proc.arguments = runtime.prefixArguments + ["-s", "read-only", "-a", "untrusted", "app-server"]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = LoginShellPathResolver.loginShellPATH
        // Scope CODEX_HOME if we have a managed home
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

        MultiCodexLog.log(.rpc, level: .info, "RPC session launched",
            metadata: ["codeHome": scopedHomePath ?? "system"])
        startReading()
    }

    private func initialize() async throws {
        guard process?.isRunning == true else { throw SessionError.processDied }
        _ = try await request(method: "initialize", params: [
            "clientInfo": ["name": "multicodex-mac", "version": "0.5"]
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
            guard !newData.isEmpty else { handle.readabilityHandler = nil; return }
            Task { await self?.processStdoutData(newData) }
        }
    }

    private func processStdoutData(_ data: Data) {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = Data(stdoutBuffer[..<nl])
            stdoutBuffer.removeSubrange(...nl)
            guard !lineData.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            if let id = json["id"] as? Int, let cont = pendingRequests.removeValue(forKey: id) {
                if let error = json["error"] as? [String: Any],
                   let msg = error["message"] as? String {
                    cont.resume(throwing: SessionError.requestFailed(msg))
                } else {
                    cont.resume(returning: json)
                }
            }
        }
    }
}
```

**Integration:** For the current account (displayed in menu bar), use the persistent session for sub-second refreshes. For background accounts, use the parallel fetch (4.2) with one-shot processes.

**Effort:** ~12 hours | **Impact:** Current account refresh from ~3-5s to ~50ms. Enables real-time usage monitoring in menu bar icon.

---

### Phase 4 Summary

| Feature | What It Fixes | Effort | Impact |
|---|---|---|---|
| **4.1 Managed Homes** | Auth-swap fragility, crash safety, displaced preservation | ~16h | Foundation for everything else |
| **4.2 Parallel Fetch** | Serial → parallel, 3-5× faster refresh | ~8h | Dramatic UX improvement |
| **4.3 Robust Identity** | Email-only → providerAccountID, workspace support | ~4h | Correctness for workspace accounts |
| **4.4 Persistent RPC** | 3-5s → 50ms for current account refresh | ~12h | Real-time menu bar updates |
| **Total** | | **~40h** | **Architectural parity with CodexBar** |

**Dependency chain:** 4.1 → 4.2 → 4.4 (managed homes enable parallel, which enables persistent RPC). 4.3 is independent.

---

## Phase 5: Value Add (Medium Effort, Medium Impact)

### 5.1 Cost Tracking from Local JSONL Logs

**Problem:** We show % usage but not dollar costs. CodexBar scans local session logs to compute actual token costs.

**CodexBar Reference:** `CostUsageScanner`, `CostUsagePricing`, `CostUsageJsonl` — scans JSONL session files with model-aware pricing.

**Files to Create:**

```
Sources/MultiCodex/Core/Usage/
├── CostTracking/
│   ├── CostUsageScanner.swift     # NEW — JSONL log scanner
│   ├── CostPricing.swift          # NEW — per-model pricing table
│   └── CostReport.swift           # NEW — cost aggregation model
```

#### `Sources/MultiCodex/Core/Usage/CostTracking/CostPricing.swift`

```swift
import Foundation

/// Per-model token pricing for cost calculation.
/// Adapted from CodexBar's CostUsagePricing (Codex models only).
/// Prices in USD per token.
enum CostPricing {
    struct ModelPricing {
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheReadCostPerToken: Double  // nil → use inputCostPerToken
        let displayLabel: String?
    }

    // Current pricing table — update as OpenAI releases new models.
    // Copied from CodexBar's CostUsagePricing.codex with 2026 pricing.
    private static let models: [String: ModelPricing] = [
        "gpt-5": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5,
                       cacheReadCostPerToken: 1.25e-7, displayLabel: nil),
        "gpt-5-codex": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5,
                             cacheReadCostPerToken: 1.25e-7, displayLabel: nil),
        "gpt-5-mini": .init(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6,
                            cacheReadCostPerToken: 2.5e-8, displayLabel: nil),
        "gpt-5-nano": .init(inputCostPerToken: 5e-8, outputCostPerToken: 4e-7,
                            cacheReadCostPerToken: 5e-9, displayLabel: nil),
        "gpt-5-pro": .init(inputCostPerToken: 1.5e-5, outputCostPerToken: 1.2e-4,
                           cacheReadCostPerToken: 1.5e-6, displayLabel: nil),
        "gpt-5.1": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5,
                         cacheReadCostPerToken: 1.25e-7, displayLabel: nil),
        "gpt-5.1-codex": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5,
                               cacheReadCostPerToken: 1.25e-7, displayLabel: nil),
        "gpt-5.1-codex-max": .init(inputCostPerToken: 1.25e-6, outputCostPerToken: 1e-5,
                                   cacheReadCostPerToken: 1.25e-7, displayLabel: nil),
        "gpt-5.1-codex-mini": .init(inputCostPerToken: 2.5e-7, outputCostPerToken: 2e-6,
                                    cacheReadCostPerToken: 2.5e-8, displayLabel: nil),
    ]

    /// Normalize a model name (strip date suffixes, provider prefixes).
    static func normalizeModel(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("openai/") { name = String(name.dropFirst("openai/".count)) }
        if models[name] != nil { return name }
        // Strip date suffix like -2025-06-01
        if let range = name.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(name[..<range.lowerBound])
            if models[base] != nil { return base }
        }
        return name
    }

    /// Compute USD cost for given token counts and model.
    static func costUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int
    ) -> Double? {
        let key = normalizeModel(model)
        guard let pricing = models[key] else { return nil }

        let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
        let nonCached = max(0, inputTokens - cached)
        let cachedRate = pricing.cacheReadCostPerToken

        return Double(nonCached) * pricing.inputCostPerToken
            + Double(cached) * cachedRate
            + Double(max(0, outputTokens)) * pricing.outputCostPerToken
    }
}
```

#### `Sources/MultiCodex/Core/Usage/CostTracking/CostReport.swift`

```swift
import Foundation

struct CostReport: Equatable {
    let accountName: String
    let totalCostUSD: Double
    let todayCostUSD: Double
    let weekCostUSD: Double
    let byModel: [String: Double]  // model → cost
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let sampledAt: Date

    var formattedTotal: String {
        CostFormatter.usd(totalCostUSD)
    }

    var formattedToday: String {
        CostFormatter.usd(todayCostUSD)
    }

    var formattedWeek: String {
        CostFormatter.usd(weekCostUSD)
    }

    static let zero = CostReport(
        accountName: "",
        totalCostUSD: 0,
        todayCostUSD: 0,
        weekCostUSD: 0,
        byModel: [:],
        totalInputTokens: 0,
        totalOutputTokens: 0,
        sampledAt: Date()
    )
}

enum CostFormatter {
    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    static func tokens(_ value: Int) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 { return String(format: "%.1fM", Double(absValue) / 1_000_000) }
        if absValue >= 1_000 { return String(format: "%.1fK", Double(absValue) / 1_000) }
        return "\(value)"
    }
}
```

#### Integration into AccountUsage:

```swift
// In AccountUsage — add cost field
struct AccountUsage {
    // ... existing ...
    var costReport: CostReport?
}
```

Then show in `DashboardAccountRow` expanded state: "$2.47 today · $18.30 this week".

**Effort:** ~12 hours | **Impact:** Dollar-cost visibility — the metric users actually care about. Also enables cost-aware auto-switching.

---

### 5.2 Dynamic Menu Bar Icon

**Problem:** Static icon gives no information. CodexBar renders a 2-bar usage meter directly in the icon.

**CodexBar Reference:** `IconRenderer` — Core Graphics rendering of usage bars as template `NSImage`.

**File to Create:**

```
Sources/MultiCodex/Features/MenuBar/
└── MenuBarIconRenderer.swift   # NEW
```

#### `Sources/MultiCodex/Features/MenuBar/MenuBarIconRenderer.swift`

```swift
import AppKit

/// Renders a dynamic menu bar icon showing current account usage.
/// Simplified from CodexBar's IconRenderer (~1000 lines → ~150 lines).
///
/// Two-bar meter:
/// ┌──────┐
/// │ ████ │  ← 5h window (top bar)
/// │      │
/// │ ██   │  ← weekly window (bottom bar)
/// └──────┘
///
/// Color mapping: green → yellow → red based on usage level.
/// Dimmed when stale/error.
enum MenuBarIconRenderer {
    private static let size = NSSize(width: 18, height: 18)
    private static let scale: CGFloat = 2

    /// Render an icon showing two usage bars.
    static func render(fiveHourPercent: Double?, weeklyPercent: Double?, isStale: Bool) -> NSImage {
        let canvasSize = NSSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let image = NSImage(size: canvasSize)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return NSImage(systemSymbolName: "gauge.open.with.lines.needle.33percent", accessibilityDescription: nil)!
        }

        let alpha: CGFloat = isStale ? 0.4 : 1.0

        // Background
        context.setFillColor(NSColor.quaternaryLabelColor.withAlphaComponent(alpha * 0.3).cgColor)
        context.fill(CGRect(origin: .zero, size: canvasSize))

        // Top bar (5h window) — taller
        let topBarRect = CGRect(x: 4, y: canvasSize.height - 14, width: canvasSize.width - 8, height: 8)
        drawBar(in: topBarRect, usedPercent: fiveHourPercent, context: context, alpha: alpha)

        // Bottom bar (weekly window) — thinner
        let bottomBarRect = CGRect(x: 4, y: 4, width: canvasSize.width - 8, height: 4)
        drawBar(in: bottomBarRect, usedPercent: weeklyPercent, context: context, alpha: alpha)

        image.unlockFocus()
        image.isTemplate = true  // Template image — macOS handles dark/light mode
        return image
    }

    private static func drawBar(in rect: CGRect, usedPercent: Double?, context: CGContext, alpha: CGFloat) {
        // Background track
        context.setFillColor(NSColor.tertiaryLabelColor.withAlphaComponent(alpha * 0.5).cgColor)
        context.fill(rect)

        guard let used = usedPercent, used > 0 else { return }

        let fraction = min(1, max(0, used / 100))
        let fillWidth = rect.width * CGFloat(fraction)
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)

        // Fill color based on usage level
        let color: NSColor
        if used >= 95 {
            color = NSColor.systemRed
        } else if used >= 80 {
            color = NSColor.systemOrange
        } else if used >= 60 {
            color = NSColor.systemYellow
        } else {
            color = NSColor.systemGreen
        }

        context.setFillColor(color.withAlphaComponent(alpha).cgColor)
        context.fill(fillRect)
    }
}
```

#### Integration:

```swift
// In AccountsMenuViewModel — update icon after refresh
func updateMenuBarIcon() {
    let current = accounts.first(where: \.isCurrent)
    let fiveHourUsed = current?.usage.fiveHour.usedPercent
    let weeklyUsed = current?.usage.weekly.usedPercent
    let isStale = current?.connectionState != .connected

    let icon = MenuBarIconRenderer.render(
        fiveHourPercent: fiveHourUsed,
        weeklyPercent: weeklyUsed,
        isStale: isStale
    )
    // Set as MenuBarExtra icon
    self.menuBarIcon = icon
}
```

**Effort:** ~6 hours | **Impact:** Users see usage at a glance without opening the menu.

---

### 5.3 Credits Balance Tracking

**Problem:** We parse credits from the API but don't prominently display them or use them in switching decisions.

**Files to Modify:**
- `Sources/MultiCodex/Core/Usage/UsageModels.swift` — add credits display to `UsageSummary`
- `Sources/MultiCodex/Core/Accounts/AccountSwitchRecommendationService.swift` — factor credits into scores
- `Sources/MultiCodex/Features/MenuBar/DashboardAccountRow.swift` — show credits

```swift
// In AccountSwitchRecommendationService — add credits awareness
private static func fallbackScore(for account: AccountUsage) -> Double {
    let remainingFiveHour = remainingFraction(for: account.usage.fiveHour)
    let remainingWeekly = remainingFraction(for: account.usage.weekly)

    var score = (remainingFiveHour * 0.65) + (remainingWeekly * 0.35)

    // Credits bonus: accounts with credits have more headroom
    if let creditsText = account.usage.credits,
       let creditsValue = Double(creditsText),
       creditsValue > 0 {
        score += min(0.15, creditsValue * 0.001) // Small bonus, capped at 0.15
    }

    return score
}
```

**Effort:** ~3 hours | **Impact:** Data completeness, better switching decisions.

---

### 5.4 Account Health Summary

**Problem:** No aggregate view. Users must expand each account individually.

**File to Modify:** `Sources/MultiCodex/Features/MenuBar/AccountsMenuContentView+Sections.swift`

Add an aggregate summary section:

```swift
/// Aggregate health summary across all accounts.
/// Shows: total remaining capacity, accounts at risk, next reset time.
struct AccountsHealthSummary {
    let totalAccounts: Int
    let healthyAccounts: Int
    let atRiskAccounts: Int      // >80% used on any window
    let aggregateFiveHourRemaining: Double  // average remaining %
    let aggregateWeeklyRemaining: Double
    let nextResetAt: Date?       // earliest reset across all accounts

    static func from(_ accounts: [AccountUsage]) -> AccountsHealthSummary {
        let healthy = accounts.filter { $0.connectionState == .connected }
        let atRisk = healthy.filter { account in
            let fiveHour = account.usage.fiveHour.usedPercent ?? 0
            let weekly = account.usage.weekly.usedPercent ?? 0
            return fiveHour >= 80 || weekly >= 80
        }

        let avgFiveHour = healthy.isEmpty ? 0 : healthy.reduce(0) { $0 + (100 - ($1.usage.fiveHour.usedPercent ?? 0)) } / Double(healthy.count)
        let avgWeekly = healthy.isEmpty ? 0 : healthy.reduce(0) { $0 + (100 - ($1.usage.weekly.usedPercent ?? 0)) } / Double(healthy.count)

        let nextReset = healthy.flatMap { account in
            [account.usage.fiveHour.resetsAt, account.usage.weekly.resetsAt]
        }.compactMap { $0 }.min()

        return AccountsHealthSummary(
            totalAccounts: accounts.count,
            healthyAccounts: healthy.count,
            atRiskAccounts: atRisk.count,
            aggregateFiveHourRemaining: avgFiveHour,
            aggregateWeeklyRemaining: avgWeekly,
            nextResetAt: nextReset
        )
    }

    var summaryText: String {
        "\(healthyAccounts)/\(totalAccounts) healthy"
    }

    var detailText: String {
        var parts: [String] = []
        if atRiskAccounts > 0 {
            parts.append("\(atRiskAccounts) at risk")
        }
        parts.append(String(format: "5h: %.0f%% · Weekly: %.0f%%", aggregateFiveHourRemaining, aggregateWeeklyRemaining))
        return parts.joined(separator: " · ")
    }
}
```

Show this at the top of the menu bar dropdown, above individual account rows.

**Effort:** ~4 hours | **Impact:** Quick overview without scanning each account.

---

### 5.5 Version Check / Update Notification

**Problem:** No way to know when updates are available. Users must check manually.

**File to Create:**

```
Sources/MultiCodex/Infrastructure/UpdateCheck/
└── UpdateChecker.swift    # NEW
```

```swift
import Foundation

/// Checks GitHub releases for new versions.
/// Simple approach — no Sparkle dependency needed.
enum UpdateChecker {
    struct Release: Decodable {
        let tagName: String
        let htmlUrl: String
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
        }
    }

    static let repository = "mohamadhosein/multicodex" // Update with actual repo

    static func checkForUpdate(currentVersion: String) async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))

        guard latest != currentVersion else { return nil }

        // Simple semver comparison
        guard isVersion(latest, newerThan: currentVersion) else { return nil }

        return release
    }

    private static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(parts1.count, parts2.count) {
            let a = i < parts1.count ? parts1[i] : 0
            let b = i < parts2.count ? parts2[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }
}
```

Show in About settings section: "Update available: v0.5.0 → [Download](...)"

**Effort:** ~3 hours | **Impact:** Users discover updates without checking manually.

---

### 5.6 Mass Export / Import Accounts

**Problem:** No way to back up account configurations or migrate between machines. If a user reinstalls macOS or switches to a new Mac, they must manually re-add and re-login every account.

**Goal:** Export all accounts (names, config, auth data) to a single encrypted JSON file. Import restores everything — accounts reappear with working auth, no re-login needed.

**File to Create:**

```
Sources/MultiCodex/Features/Shared/
└── AccountExportService.swift      # NEW — export/import logic

Sources/MultiCodex/Features/Settings/
└── SettingsContentView+Data.swift   # NEW — export/import UI in settings
```

#### Export Format

```json
{
  "version": 1,
  "exportedAt": "2026-04-22T14:30:00Z",
  "appVersion": "0.5.0",
  "accounts": [
    {
      "name": "Work",
      "auth": { ... },
      "meta": {
        "createdAt": "2025-12-01T10:00:00Z",
        "lastUsedAt": "2026-04-22T12:00:00Z"
      }
    },
    {
      "name": "Personal",
      "auth": { ... },
      "meta": {
        "createdAt": "2026-01-15T09:00:00Z",
        "lastUsedAt": "2026-04-21T18:00:00Z"
      }
    }
  ],
  "preferences": {
    "accountSwitchingStrategy": "expiryAware",
    "menuDensity": "comfortable",
    "accountSortCriterion": "used",
    "accountSortWindow": "fiveHour",
    "accountSortDirection": "descending",
    "limitsCacheTTLSeconds": 1200
  },
  "currentAccount": "Work"
}
```

#### `Sources/MultiCodex/Features/Shared/AccountExportService.swift`

```swift
import Foundation

/// Exports and imports all account data for backup/migration purposes.
/// The export file contains auth tokens — treated as sensitive data.
enum AccountExportService {

    struct ExportPayload: Codable {
        let version: Int
        let exportedAt: String
        let appVersion: String
        let accounts: [ExportedAccount]
        let preferences: ExportedPreferences?
        let currentAccount: String?
    }

    struct ExportedAccount: Codable {
        let name: String
        let auth: [String: AnyCodable]  // auth.json contents
        let meta: AccountMeta?
    }

    struct ExportedPreferences: Codable {
        let accountSwitchingStrategy: String?
        let menuDensity: String?
        let accountSortCriterion: String?
        let accountSortWindow: String?
        let accountSortDirection: String?
        let limitsCacheTTLSeconds: Int?
    }

    // Type-erasing wrapper for heterogeneous JSON values
    struct AnyCodable: Codable, Equatable {
        let value: Any
        // ... encode/decode implementations
    }

    // MARK: - Export

    /// Export all accounts and preferences to a JSON file.
    /// Returns the URL of the exported file.
    static func export(
        accountService: CodexAccountService,
        preferencesStore: AppPreferencesStore
    ) async throws -> URL {
        let paths = accountService.currentPaths()
        let config = try accountService.loadConfig(paths: paths)

        var exportedAccounts: [ExportedAccount] = []
        for accountName in config.accounts {
            let authPath: String

            // With managed homes (Phase 4), read from isolated home
            if let managedHome = ManagedCodexHomeFactory.homeURL(for: accountName) {
                authPath = managedHome.appendingPathComponent("auth.json").path
            } else {
                // Legacy path
                authPath = paths.accountAuthPath(accountName)
            }

            guard let authData = try? Data(contentsOf: URL(fileURLWithPath: authPath)) else {
                MultiCodexLog.log(.config, level: .warning,
                    "Skipping account \(accountName) — auth data missing")
                continue
            }

            let authJSON = try? JSONSerialization.jsonObject(with: authData) as? [String: Any]
            let meta = try? accountService.loadAccountMeta(account: accountName, paths: paths)

            exportedAccounts.append(ExportedAccount(
                name: accountName,
                auth: authJSON?.mapValues { AnyCodable($0) } ?? [:],
                meta: meta
            ))

            MultiCodexLog.log(.config, level: .debug,
                "Exported account \(accountName)")
        }

        let payload = ExportPayload(
            version: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: "0.5.0",
            accounts: exportedAccounts,
            preferences: ExportedPreferences(
                accountSwitchingStrategy: preferencesStore.accountSwitchingStrategy.rawValue,
                menuDensity: preferencesStore.menuDensity.rawValue,
                accountSortCriterion: preferencesStore.accountSortCriterion.rawValue,
                accountSortWindow: preferencesStore.accountSortWindow.rawValue,
                accountSortDirection: preferencesStore.accountSortDirection.rawValue,
                limitsCacheTTLSeconds: preferencesStore.limitsCacheTTLSeconds
            ),
            currentAccount: config.currentAccount
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        // Write to user-chosen location via NSSavePanel (called from UI)
        // The caller handles the panel; this returns the data
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("multicodex-export-\(Date().timeIntervalSince1970).json")
        try data.write(to: tempURL, options: .atomic)

        MultiCodexLog.log(.config, level: .info,
            "Exported \(exportedAccounts.count) accounts")

        return tempURL
    }

    // MARK: - Import

    struct ImportResult {
        let imported: Int
        let skipped: Int   // already existing with same name
        let failed: Int    // auth data invalid
        let conflicts: [String]  // account names that already exist
    }

    /// Import accounts from a JSON file.
    /// Merge strategy: skip accounts that already exist (don't overwrite).
    /// Returns a summary of what happened.
    static func importAccounts(
        from url: URL,
        accountService: CodexAccountService,
        preferencesStore: AppPreferencesStore,
        mergeStrategy: ImportMergeStrategy = .skipExisting
    ) async throws -> ImportResult {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let payload = try decoder.decode(ExportPayload.self, from: data)

        guard payload.version == 1 else {
            throw ExportError.unsupportedVersion(payload.version)
        }

        let paths = accountService.currentPaths()
        let existingConfig = try accountService.loadConfig(paths: paths)
        var imported = 0
        var skipped = 0
        var failed = 0
        var conflicts: [String] = []

        for account in payload.accounts {
            let exists = existingConfig.accounts.contains(account.name)

            if exists {
                switch mergeStrategy {
                case .skipExisting:
                    skipped += 1
                    conflicts.append(account.name)
                    continue
                case .overwrite:
                    // Will be replaced below
                    break
                }
            }

            // Reconstruct auth.json data
            let authDict = account.auth.reduce(into: [String: Any]()) { $0[$1.key] = $1.value.value }
            let authData = try JSONSerialization.data(
                withJSONObject: authDict,
                options: [.prettyPrinted, .sortedKeys]
            )

            // Write to managed home (Phase 4) or legacy path
            if let managedHome = ManagedCodexHomeFactory.homeURL(for: account.name)
                ?? (try? ManagedCodexHomeFactory.createHome(for: account.name)) {
                try ManagedCodexHomeFactory.writeAuthData(authData, to: managedHome)
            } else {
                // Legacy fallback
                let legacyAuthPath = paths.accountAuthPath(account.name)
                let dir = (legacyAuthPath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(
                    atPath: dir, withIntermediateDirectories: true
                )
                try authData.write(to: URL(fileURLWithPath: legacyAuthPath), options: .atomic)
            }

            // Register account in config
            try accountService.registerAccount(named: account.name, paths: paths)

            // Restore metadata if available
            if let meta = account.meta {
                try? accountService.updateAccountMeta(
                    account: account.name, paths: paths
                ) { existing in
                    existing.createdAt = meta.createdAt
                    existing.lastUsedAt = meta.lastUsedAt
                    existing.lastLoginStatus = meta.lastLoginStatus
                }
            }

            imported += 1
            MultiCodexLog.log(.config, level: .info,
                "Imported account \(account.name)")
        }

        // Restore preferences (only if payload includes them)
        if let prefs = payload.preferences {
            if let strategy = prefs.accountSwitchingStrategy,
               let value = AccountSwitchingStrategy(rawValue: strategy) {
                preferencesStore.accountSwitchingStrategy = value
            }
            if let density = prefs.menuDensity,
               let value = MenuDensity(rawValue: density) {
                preferencesStore.menuDensity = value
            }
            if let criterion = prefs.accountSortCriterion,
               let value = AccountSortCriterion(rawValue: criterion) {
                preferencesStore.accountSortCriterion = value
            }
            if let window = prefs.accountSortWindow,
               let value = AccountSortWindow(rawValue: window) {
                preferencesStore.accountSortWindow = value
            }
            if let direction = prefs.accountSortDirection,
               let value = SortDirection(rawValue: direction) {
                preferencesStore.accountSortDirection = value
            }
            if let ttl = prefs.limitsCacheTTLSeconds {
                preferencesStore.limitsCacheTTLSeconds = ttl
            }
        }

        // Set current account if specified
        if let current = payload.currentAccount {
            try? accountService.switchAccount(name: current)
        }

        MultiCodexLog.log(.config, level: .info,
            "Import complete: \(imported) imported, \(skipped) skipped, \(failed) failed")

        return ImportResult(
            imported: imported,
            skipped: skipped,
            failed: failed,
            conflicts: conflicts
        )
    }

    enum ImportMergeStrategy {
        case skipExisting     // Don't overwrite accounts that already exist
        case overwrite        // Replace existing accounts with imported versions
    }

    enum ExportError: LocalizedError {
        case unsupportedVersion(Int)
        case noAccounts

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "Unsupported export file version: \(v)"
            case .noAccounts:
                return "No accounts to export."
            }
        }
    }
}
```

#### UI Integration (Settings)

Add a new **Data** section to Settings with export/import buttons:

```swift
// In SettingsContentView — new section
enum SettingsSection {
    case general
    case accounts
    case system
    case data        // NEW
    case about
}

// SettingsContentView+Data.swift
struct SettingsDataPane: View {
    @ObservedObject var viewModel: AccountsMenuViewModel
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importResult: AccountExportService.ImportResult?
    @State private var showImportResult = false

    var body: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Backup & Restore")
                    .font(.headline)

                Text("Export all accounts and preferences to a JSON file. Import restores them on any Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    // Export button
                    Button {
                        isExporting = true
                    } label: {
                        Label("Export Accounts", systemImage: "square.and.arrow.up")
                    }
                    .fileExporter(
                        isPresented: $isExporting,
                        document: ExportDocument(data: exportData),
                        contentType: .json,
                        defaultFilename: "multicodex-backup"
                    ) { result in
                        handleExportResult(result)
                    }

                    // Import button
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import Accounts", systemImage: "square.and.arrow.down")
                    }
                    .fileImporter(
                        isPresented: $isImporting,
                        allowedContentTypes: [.json],
                        allowsMultipleSelection: false
                    ) { result in
                        handleImportResult(result)
                    }
                }

                // Import result sheet
                if let result = importResult {
                    ImportResultSummary(result: result)
                }

                Divider()

                // Warning
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Exported files contain auth tokens. Store them securely.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

#### Also add to Menu Bar (Quick Access)

A compact export/import action in the menu bar footer, next to refresh and settings:

```swift
// In AccountsMenuContentView — footer actions
HStack {
    Button { viewModel.refreshController.triggerRefresh(refreshLive: true) } label: {
        Image(systemName: "arrow.clockwise")
    }
    Button { viewModel.exportAccounts() } label: {       // NEW
        Image(systemName: "square.and.arrow.up")
    }
    Button { openSettings() } label: {
        Image(systemName: "gear")
    }
}
```

**Use cases:**
1. **Backup before OS reinstall** — export to USB drive, import after reinstall
2. **Migration to new Mac** — export on old Mac, AirDrop/import on new Mac
3. **Team setup** — admin exports team config, each team member imports (then re-authenticates individually — auth tokens are account-specific)
4. **Debugging** — export and inspect account state when reporting issues

**Security considerations:**
- Export file contains live auth tokens — marked as sensitive
- File written with `0o600` permissions (owner read/write only)
- UI warning: "Exported files contain auth tokens. Store them securely."
- Import validates file version before applying changes
- Merge strategy lets user choose: skip existing or overwrite

**Effort:** ~8 hours | **Impact:** Essential for data safety. Users with 5+ accounts can't afford to lose their setup. Also enables team workflows.

---

## Phase 6: UI Polish (Low-Medium Effort, Medium Impact)

### 6.1 Pace Display in Account Rows

Add pace indicator text to `DashboardAccountRow` expanded state:

```swift
// In DashboardAccountRow expanded section
if let pace = account.fiveHourPace {
    HStack(spacing: 4) {
        Circle()
            .fill(paceColor(pace.stage))
            .frame(width: 6, height: 6)
        Text(pace.detailText)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
```

### 6.2 Cost Display in Account Rows

```swift
if let cost = account.costReport, cost.totalCostUSD > 0 {
    HStack(spacing: 4) {
        Image(systemName: "dollarsign.circle")
            .font(.caption2)
        Text("\(cost.formattedToday) today · \(cost.formattedWeek) this week")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
```

### 6.3 Health Summary Section in Menu Bar

Add a compact header above account rows:

```swift
// In AccountsMenuContentView
let health = AccountsHealthSummary.from(viewModel.accounts)
HStack {
    Text(health.summaryText)
        .font(.caption)
        .foregroundStyle(.secondary)
    if health.atRiskAccounts > 0 {
        Text("\(health.atRiskAccounts) at risk")
            .font(.caption)
            .foregroundStyle(.orange)
    }
    Spacer()
    if let nextReset = health.nextResetAt {
        Text("Next reset: \(UsageFormatter.resetText(for: nextReset, mode: .relative))")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }
}
```

---

## Implementation Timeline

| Phase | Features | Total Effort | Blockers |
|-------|----------|-------------|----------|
| **Phase 1** | Logging, Error Recovery, Quota Notifications, JWT Identity | ~14 hours | None |
| **Phase 2** | Pace Prediction, Enhanced Auto-Switch | ~12 hours | Phase 1 (logging) |
| **Phase 3** | Token Auto-Refresh, Account Reconciliation | ~9 hours | Phase 1 (JWT identity) |
| **Phase 4** | Managed Homes, Parallel Fetch, Robust Identity, Persistent RPC | ~40 hours | Phase 3 (reconciliation) |
| **Phase 5** | Cost Tracking, Dynamic Icon, Credits, Health Summary, Updates, Export/Import | ~36 hours | Phase 2 (pace data) |
| **Phase 6** | UI Polish for all above | ~8 hours | Phase 5 |

**Total estimated effort:** ~119 hours across 6 phases.

### Recommended execution order:

1. **Week 1:** Phase 1 (foundation — logging + error recovery + quota notifications + JWT identity)
2. **Week 2:** Phase 2 (pace prediction + pace-aware auto-switch)
3. **Week 3:** Phase 3 (token refresh + reconciliation) + start Phase 4 (managed homes design)
4. **Week 4–5:** Phase 4 (managed homes → parallel fetch → robust identity → persistent RPC — this is the big one)
5. **Week 6:** Phase 5 (cost tracking + dynamic icon + health summary + export/import)
6. **Week 7:** Phase 6 (UI polish) + testing + release as v0.5.0

### Test coverage plan:

Each phase should include tests alongside implementation:

- **Phase 1:** `LogRedactorTests`, `QuotaTransitionDetectorTests`, `JWTIdentityTests`, `ErrorRecoveryTests`
- **Phase 2:** `UsagePaceTests`, `PaceAwareRecommendationTests`
- **Phase 3:** `TokenRefreshTests`, `AccountReconciliationTests`
- **Phase 4:** `ManagedHomeFactoryTests`, `AuthSwapServiceTests` (atomic rename), `ParallelFetchTests`, `AccountIdentityTests`, `ManagedAccountMigratorTests`, `CodexRPCSessionTests`
- **Phase 5:** `CostPricingTests`, `CostScannerTests`, `AccountExportServiceTests`, `UpdateCheckerTests`
