import Foundation

enum PaceStatus: String {
    case ahead
    case onTrack = "on-track"
    case behind

    var label: String {
        switch self {
        case .ahead:
            return "ahead"
        case .onTrack:
            return "on track"
        case .behind:
            return "behind"
        }
    }
}

enum ResetDisplayMode: String, CaseIterable {
    case relative
    case absolute

    var buttonLabel: String {
        switch self {
        case .relative:
            return "Reset: Relative"
        case .absolute:
            return "Reset: Absolute"
        }
    }

    var next: Self {
        switch self {
        case .relative:
            return .absolute
        case .absolute:
            return .relative
        }
    }
}

struct UsageMetric {
    let label: String
    let percentText: String
    let usedPercent: Double?
    let periodMinutes: Int?
    let resetsAt: Date?
    let paceStatus: PaceStatus?

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

struct ProfileUsage: Identifiable {
    let name: String
    let isCurrent: Bool
    let hasAuth: Bool
    let lastUsedAt: String?
    let lastLoginStatus: String?
    let usage: UsageSummary
    let source: String
    let usageError: String?

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

    var lastUsedLabel: String {
        guard let raw = lastUsedAt else {
            return "never"
        }

        guard let date = UsageFormatter.parseISODate(raw) else {
            return raw
        }

        return UsageFormatter.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
