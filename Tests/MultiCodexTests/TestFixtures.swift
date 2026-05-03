import Foundation
import XCTest
@testable import MultiCodex

// MARK: - Test Utilities

/// Creates an isolated UserDefaults suite for testing.
/// Automatically cleans up the suite after test completion.
func makeEphemeralDefaults() -> UserDefaults {
    let suite = "MultiCodexTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else {
        XCTFail("Could not create isolated UserDefaults suite: \(suite)")
        return .standard
    }
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

// MARK: - Account Entry Fixtures

func makeAccountEntry(
    name: String,
    isCurrent: Bool = false,
    hasAuth: Bool = true,
    lastUsedAt: String? = nil,
    lastLoginStatus: String? = nil,
    defaultWorkspaceEmail: String? = nil
) -> AccountEntry {
    AccountEntry(
        name: name,
        isCurrent: isCurrent,
        hasAuth: hasAuth,
        lastUsedAt: lastUsedAt,
        lastLoginStatus: lastLoginStatus,
        defaultWorkspaceEmail: defaultWorkspaceEmail
    )
}

// MARK: - Usage Fixtures

struct UsageFixtures {
    static func makeUsageMetric(
        label: String = "Test",
        percentText: String = "45%",
        usedPercent: Double? = 45.0,
        periodMinutes: Int? = 300,
        resetsAt: Date? = nil
    ) -> UsageMetric {
        UsageMetric(
            label: label,
            percentText: percentText,
            usedPercent: usedPercent,
            periodMinutes: periodMinutes,
            resetsAt: resetsAt ?? Date().addingTimeInterval(3600)
        )
    }

    static func makeEmptyUsageSummary() -> UsageSummary {
        UsageSummary(
            fiveHour: UsageMetric(label: "5h", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil),
            weekly: UsageMetric(label: "weekly", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil),
            credits: "-"
        )
    }

    static func makeUsageSummary(
        fiveHour: UsageMetric? = nil,
        weekly: UsageMetric? = nil,
        credits: String = "-"
    ) -> UsageSummary {
        UsageSummary(
            fiveHour: fiveHour ?? makeUsageMetric(label: "5h", periodMinutes: 300),
            weekly: weekly ?? makeUsageMetric(label: "Weekly", periodMinutes: 10080),
            credits: credits
        )
    }

    static func makeAccountUsage(
        name: String,
        isCurrent: Bool = false,
        hasAuth: Bool = true,
        usage: UsageSummary? = nil
    ) -> AccountUsage {
        AccountUsage(
            name: name,
            isCurrent: isCurrent,
            hasAuth: hasAuth,
            lastUsedAt: nil,
            lastLoginStatus: nil,
            usage: usage ?? makeEmptyUsageSummary(),
            source: "",
            usageError: nil
        )
    }
}
