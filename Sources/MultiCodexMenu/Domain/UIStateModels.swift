import Foundation

enum SettingsSection: String, CaseIterable, Identifiable {
    case dashboard
    case profiles
    case runtime
    case display
    case troubleshooting
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .profiles:
            return "Profiles"
        case .runtime:
            return "Runtime"
        case .display:
            return "Display"
        case .troubleshooting:
            return "Troubleshooting"
        case .advanced:
            return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard:
            return "rectangle.grid.2x2"
        case .profiles:
            return "person.2"
        case .runtime:
            return "terminal"
        case .display:
            return "paintbrush"
        case .troubleshooting:
            return "wrench.and.screwdriver"
        case .advanced:
            return "gearshape.2"
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

struct MenuAlertState {
    enum Severity: Equatable {
        case runtimeUnavailable
        case refreshError
        case authRequired
    }

    enum Action: Equatable {
        case openRuntimeSettings
        case refreshLive
        case relogin(profileName: String)
    }

    let severity: Severity
    let title: String
    let message: String
    let actionTitle: String
    let action: Action
}

struct ProfileRowState: Identifiable {
    enum PrimaryAction: Equatable {
        case none
        case switchProfile
        case relogin

        var title: String {
            switch self {
            case .none:
                return ""
            case .switchProfile:
                return "Switch"
            case .relogin:
                return "Re-login"
            }
        }

        var symbol: String {
            switch self {
            case .none:
                return ""
            case .switchProfile:
                return "checkmark.circle.fill"
            case .relogin:
                return "person.crop.circle.badge.plus"
            }
        }
    }

    let profile: ProfileUsage
    let resetDisplayMode: ResetDisplayMode

    var id: String { profile.name }

    var name: String { profile.name }
    var isCurrent: Bool { profile.isCurrent }
    var connectionState: ProfileConnectionState { profile.connectionState }
    var fiveHourPercent: String { profile.usage.fiveHour.percentText }
    var weeklyPercent: String { profile.usage.weekly.percentText }
    var resetText: String {
        profile.usage.fiveHour.resetText(mode: resetDisplayMode)
    }

    var primaryAction: PrimaryAction {
        if profile.connectionState == .needsLogin {
            return .relogin
        }
        if !profile.isCurrent {
            return .switchProfile
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

struct PendingProfileRemovalRequest: Identifiable {
    let profileName: String
    let deleteData: Bool

    var id: String {
        "\(profileName)|\(deleteData)"
    }
}
