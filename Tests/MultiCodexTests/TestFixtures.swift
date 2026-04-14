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
}
