import Foundation

/// Detects quota depletion/restoration transitions between refresh cycles.
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
        case depleted
        case restored
        case none
    }

    /// Remaining percentage at or below this value is considered depleted.
    static let depletedRemainingThreshold: Double = 0.5

    static func isDepleted(usedPercent: Double?) -> Bool {
        guard let usedPercent else {
            return false
        }
        return 100 - usedPercent <= depletedRemainingThreshold
    }

    static func detectTransitions(
        previous: [AccountUsage],
        current: [AccountUsage]
    ) -> [WindowTransition] {
        guard !previous.isEmpty, !current.isEmpty else {
            return []
        }

        let previousByName = Dictionary(uniqueKeysWithValues: previous.map { ($0.name, $0) })
        var transitions: [WindowTransition] = []

        for account in current {
            guard let previousAccount = previousByName[account.name] else {
                continue
            }

            let fiveHour = detectWindowTransition(
                previousUsed: previousAccount.usage.fiveHour.usedPercent,
                currentUsed: account.usage.fiveHour.usedPercent
            )
            if fiveHour != .none {
                transitions.append(WindowTransition(accountName: account.name, window: .fiveHour, transition: fiveHour))
            }

            let weekly = detectWindowTransition(
                previousUsed: previousAccount.usage.weekly.usedPercent,
                currentUsed: account.usage.weekly.usedPercent
            )
            if weekly != .none {
                transitions.append(WindowTransition(accountName: account.name, window: .weekly, transition: weekly))
            }
        }

        return transitions
    }

    private static func detectWindowTransition(
        previousUsed: Double?,
        currentUsed: Double?
    ) -> QuotaTransition {
        let wasDepleted = isDepleted(usedPercent: previousUsed)
        let isNowDepleted = isDepleted(usedPercent: currentUsed)

        if !wasDepleted, isNowDepleted {
            return .depleted
        }
        if wasDepleted, !isNowDepleted {
            return .restored
        }
        return .none
    }
}
