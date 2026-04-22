import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case accounts
    case system
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .accounts:
            return "Accounts"
        case .system:
            return "System"
        case .about:
            return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "gear"
        case .accounts:
            return "person.2"
        case .system:
            return "cpu"
        case .about:
            return "info.circle"
        }
    }
}

enum MenuDensity: String, CaseIterable, Identifiable {
    case compact
    case comfortable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return "Compact"
        case .comfortable:
            return "Comfortable"
        }
    }
}

enum UsageBarStyle: String, CaseIterable, Identifiable {
    case depleting
    case filling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .depleting:
            return "Remaining"
        case .filling:
            return "Used"
        }
    }

    var descriptionText: String {
        switch self {
        case .depleting:
            return "Remaining mode: bars start full and empty as you consume limits."
        case .filling:
            return "Used mode: bars start empty and fill as you consume limits."
        }
    }
}

enum AccountSortCriterion: String, CaseIterable, Identifiable {
    case used
    case remaining
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .used:
            return "Used"
        case .remaining:
            return "Remaining"
        case .name:
            return "Name"
        }
    }
}

enum AccountSortWindow: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour:
            return "5h"
        case .weekly:
            return "Weekly"
        }
    }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ascending:
            return "Ascending"
        case .descending:
            return "Descending"
        }
    }

    var shortTitle: String {
        switch self {
        case .ascending:
            return "Asc"
        case .descending:
            return "Desc"
        }
    }

    var arrowSymbol: String {
        switch self {
        case .ascending:
            return "↑"
        case .descending:
            return "↓"
        }
    }
}

struct MenuAlertState {
    enum Severity: Equatable {
        case runtimeUnavailable
        case refreshError
        case authRequired
    }

    enum Action: Equatable {
        case openRuntimeSettings
        case refreshLive
        case relogin(accountName: String)
    }

    let severity: Severity
    let title: String
    let message: String
    let actionTitle: String
    let action: Action
}

struct AccountRowState: Identifiable {
    enum PrimaryAction: Equatable {
        case none
        case switchAccount
        case relogin

        var title: String {
            switch self {
            case .none:
                return ""
            case .switchAccount:
                return "Switch"
            case .relogin:
                return "Re-login"
            }
        }

        var symbol: String {
            switch self {
            case .none:
                return ""
            case .switchAccount:
                return "checkmark.circle.fill"
            case .relogin:
                return "person.crop.circle.badge.plus"
            }
        }
    }

    let account: AccountUsage
    let resetDisplayMode: ResetDisplayMode

    var id: String { account.name }

    var name: String { account.name }
    var isCurrent: Bool { account.isCurrent }
    var connectionState: AccountConnectionState { account.connectionState }
    var defaultWorkspaceEmail: String? { account.defaultWorkspaceEmail }
    var workspaceEmailHint: String? { account.workspaceEmailHint }
    var resetText: String {
        account.usage.fiveHour.resetText(mode: resetDisplayMode)
    }

    var primaryAction: PrimaryAction {
        if account.connectionState == .needsLogin {
            return .relogin
        }
        if !account.isCurrent {
            return .switchAccount
        }
        return .none
    }
}

enum OnboardingStep: String {
    case runtime
    case login
    case verify
    case done

    var title: String {
        switch self {
        case .runtime:
            return "Runtime Check"
        case .login:
            return "First Login"
        case .verify:
            return "Verify Setup"
        case .done:
            return "Done"
        }
    }
}

struct OnboardingState {
    let step: OnboardingStep

    var isComplete: Bool {
        step == .done
    }
}

enum InteractiveLoginSessionPhase: Equatable {
    case waitingForExternalCompletion
    case needsRetry
}

struct PendingInteractiveLoginSession {
    let accountName: String
    let loginSandboxHome: String
    let shouldApplyAccountAuthOnSuccess: Bool
    let successFallback: String
    let createIfNeeded: Bool
    let phase: InteractiveLoginSessionPhase

    var id: String {
        "\(accountName)|\(loginSandboxHome)"
    }

    func withPhase(_ phase: InteractiveLoginSessionPhase) -> Self {
        PendingInteractiveLoginSession(
            accountName: accountName,
            loginSandboxHome: loginSandboxHome,
            shouldApplyAccountAuthOnSuccess: shouldApplyAccountAuthOnSuccess,
            successFallback: successFallback,
            createIfNeeded: createIfNeeded,
            phase: phase
        )
    }
}

enum SequentialLoginItemStatus: String {
    case pending
    case inProgress
    case success
    case failed
    case cancelled
}

struct SequentialLoginItem: Identifiable {
    let id: UUID
    let accountName: String
    var resolvedAccountName: String?
    var status: SequentialLoginItemStatus
    var message: String?
    var didCleanup: Bool

    init(
        id: UUID = UUID(),
        accountName: String,
        resolvedAccountName: String? = nil,
        status: SequentialLoginItemStatus = .pending,
        message: String? = nil,
        didCleanup: Bool = false
    ) {
        self.id = id
        self.accountName = accountName
        self.resolvedAccountName = resolvedAccountName
        self.status = status
        self.message = message
        self.didCleanup = didCleanup
    }
}

struct SequentialLoginState {
    static let maxAccountCount = 5

    var items: [SequentialLoginItem]
    var isRunning: Bool
    var cancellationRequested: Bool
    var currentIndex: Int?
    var startedAt: Date?
    var finishedAt: Date?

    init(
        items: [SequentialLoginItem],
        isRunning: Bool = false,
        cancellationRequested: Bool = false,
        currentIndex: Int? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.items = items
        self.isRunning = isRunning
        self.cancellationRequested = cancellationRequested
        self.currentIndex = currentIndex
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    var totalCount: Int { items.count }
    var completedCount: Int { items.filter { $0.status == .success || $0.status == .failed || $0.status == .cancelled }.count }
    var attemptedCount: Int { items.filter { $0.status != .pending }.count }
    var successCount: Int { items.filter { $0.status == .success }.count }
    var failedCount: Int { items.filter { $0.status == .failed }.count }
    var cancelledCount: Int { items.filter { $0.status == .cancelled }.count }
    var pendingCount: Int { items.filter { $0.status == .pending }.count }
    var isFinished: Bool { !isRunning && finishedAt != nil }
    var hasFailures: Bool { failedCount > 0 }
}
