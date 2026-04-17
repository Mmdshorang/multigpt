import SwiftUI

enum DashboardTokens {
    static let background = Color(red: 0.05, green: 0.055, blue: 0.07)
    static let cardBackground = Color.white.opacity(0.028)
    static let cardBorder = Color.white.opacity(0.06)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.32)
    static let accent = Color(red: 0.45, green: 0.42, blue: 0.95)
    static let accentBackground = accent.opacity(0.12)
    static let statusGreen = Color(red: 0.25, green: 0.82, blue: 0.58)
    static let statusOrange = Color(red: 0.96, green: 0.58, blue: 0.28)
    static let statusRed = Color(red: 0.92, green: 0.32, blue: 0.32)
    static let ringFiveHour = accent
    static let ringWeekly = statusGreen
    static let sparkDefault = accent.opacity(0.4)
    static let sparkHigh = statusOrange.opacity(0.5)
    static let sparkCritical = statusRed.opacity(0.5)
    static let inputBackground = Color.white.opacity(0.04)
    static let inputBorder = Color.white.opacity(0.08)
    static let inputBorderFocused = accent.opacity(0.5)
    static let toggleTrackOff = Color.white.opacity(0.12)
    static let toggleTrackOn = accent
    static let destructive = Color(red: 0.92, green: 0.32, blue: 0.32)
    static let destructiveBackground = destructive.opacity(0.10)
    static let destructiveBorder = destructive.opacity(0.25)
    static let segmentedActiveBackground = accent.opacity(0.18)
    static let segmentedActiveBorder = accent.opacity(0.35)
    static let segmentedInactiveBackground = Color.white.opacity(0.03)
    static let segmentedTrackBackground = Color.white.opacity(0.02)
    static let sidebarSelectedBackground = accent.opacity(0.10)
    static let sidebarHoverBackground = Color.white.opacity(0.04)

    enum Spacing {
        static let containerPadding: CGFloat = 16
        static let cardPadding: CGFloat = 12
        static let cardRadius: CGFloat = 10
        static let cardGap: CGFloat = 8
        static let sectionSpacing: CGFloat = 10
        static let rowGap: CGFloat = 3
        static let rowHPadding: CGFloat = 12
        static let rowVPadding: CGFloat = 10
        static let rowRadius: CGFloat = 10
        static let ringSize: CGFloat = 46
        static let dotSize: CGFloat = 7
        static let sparkHeight: CGFloat = 24
        static let footerSpacing: CGFloat = 8
    }

    enum Font {
        static func sectionLabel() -> SwiftUI.Font {
            .system(size: 9, weight: .semibold)
        }

        static func cardHeading() -> SwiftUI.Font {
            .system(size: 13, weight: .semibold)
        }

        static func detailTitle() -> SwiftUI.Font {
            .system(size: 17, weight: .bold)
        }

        static func accountName() -> SwiftUI.Font {
            .system(size: 13, weight: .semibold)
        }

        static func metadata() -> SwiftUI.Font {
            .system(size: 11, weight: .regular)
        }

        static func ringLabel() -> SwiftUI.Font {
            .system(size: 10, weight: .semibold)
        }

        static func button() -> SwiftUI.Font {
            .system(size: 11, weight: .regular)
        }
    }
}
