import Foundation

enum UsageLevel {
    case normal
    case warning
    case critical

    static func from(usedPercent: Double?) -> Self {
        guard let usedPercent else {
            return .normal
        }
        if usedPercent >= 95 {
            return .critical
        }
        if usedPercent >= 80 {
            return .warning
        }
        return .normal
    }
}

enum AccountConnectionState {
    case connected
    case needsLogin
    case error

    var label: String {
        switch self {
        case .connected:
            return "Connected"
        case .needsLogin:
            return "Needs Login"
        case .error:
            return "Error"
        }
    }
}

enum ResetDisplayMode: String, CaseIterable {
    case relative
    case absolute

    var title: String {
        switch self {
        case .relative:
            return "Relative"
        case .absolute:
            return "Absolute"
        }
    }

    var descriptionText: String {
        switch self {
        case .relative:
            return "Show reset times as relative values like \"in 2h\"."
        case .absolute:
            return "Show reset times as exact dates and clock times."
        }
    }
}

struct UsageMetric {
    let label: String
    let percentText: String
    let usedPercent: Double?
    let periodMinutes: Int?
    let resetsAt: Date?

    var normalizedFraction: Double {
        guard let usedPercent else {
            return 0
        }
        return min(1, max(0, usedPercent / 100))
    }

    func resetText(mode: ResetDisplayMode) -> String {
        UsageFormatter.resetText(for: resetsAt, mode: mode)
    }
}

struct UsageSummary {
    let fiveHour: UsageMetric
    let weekly: UsageMetric
    let credits: String
}

struct AccountUsage: Identifiable {
    let name: String
    let isCurrent: Bool
    let hasAuth: Bool
    let lastUsedAt: String?
    let lastLoginStatus: String?
    let defaultWorkspaceEmail: String?
    let usage: UsageSummary
    let source: String
    let usageError: String?

    init(
        name: String,
        isCurrent: Bool,
        hasAuth: Bool,
        lastUsedAt: String?,
        lastLoginStatus: String?,
        defaultWorkspaceEmail: String? = nil,
        usage: UsageSummary,
        source: String,
        usageError: String?
    ) {
        self.name = name
        self.isCurrent = isCurrent
        self.hasAuth = hasAuth
        self.lastUsedAt = lastUsedAt
        self.lastLoginStatus = lastLoginStatus
        self.defaultWorkspaceEmail = defaultWorkspaceEmail
        self.usage = usage
        self.source = source
        self.usageError = usageError
    }

    var id: String { name }

    var primaryPercentText: String? {
        if usage.fiveHour.percentText != "-" {
            return usage.fiveHour.percentText
        }
        if usage.weekly.percentText != "-" {
            return usage.weekly.percentText
        }
        return nil
    }

    var workspaceEmailHint: String? {
        guard let defaultWorkspaceEmail,
              !defaultWorkspaceEmail.isEmpty,
              defaultWorkspaceEmail.localizedCaseInsensitiveCompare(name) != .orderedSame
        else {
            return nil
        }
        return defaultWorkspaceEmail
    }

    var lastLoginStatusPreview: String? {
        guard let value = lastLoginStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let maxCount = 72
        guard value.count > maxCount else {
            return value
        }

        let end = value.index(value.startIndex, offsetBy: maxCount)
        return String(value[..<end]) + "..."
    }

    var lastLoginStatusDetail: String? {
        guard let value = lastLoginStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    var lastUsedLabel: String {
        guard let raw = lastUsedAt else {
            return "never"
        }

        guard let date = UsageFormatter.parseISODate(raw) else {
            return raw
        }

        return UsageFormatter.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    var connectionState: AccountConnectionState {
        if !hasAuth {
            return .needsLogin
        }
        if usageError != nil {
            return .error
        }
        return .connected
    }

    var connectionHint: String? {
        switch connectionState {
        case .connected:
            return nil
        case .needsLogin:
            if let status = lastLoginStatusPreview, !status.isEmpty {
                return "Needs login: \(status)"
            }
            return "Needs login: no active auth found."
        case .error:
            if let usageError, !usageError.isEmpty {
                return "Error: \(usageError)"
            }
            return "Error: refresh failed."
        }
    }

    var connectionDetail: String? {
        switch connectionState {
        case .connected:
            return nil
        case .needsLogin:
            if let status = lastLoginStatusDetail, !status.isEmpty {
                return status
            }
            return "No active auth was found for this account."
        case .error:
            if let usageError, !usageError.isEmpty {
                return usageError
            }
            return "The latest refresh failed."
        }
    }
}
