import SwiftUI

enum DashboardTokens {
    private static let uiScale: CGFloat = 0.84

    static func scaled(_ value: CGFloat) -> CGFloat {
        value * uiScale
    }

    static let background = Color(red: 0.075, green: 0.082, blue: 0.101)
    static let backgroundElevated = Color(red: 0.104, green: 0.112, blue: 0.135)
    static let backgroundTop = Color(red: 0.118, green: 0.127, blue: 0.154)
    static let backgroundBottom = Color(red: 0.060, green: 0.067, blue: 0.084)
    static let cardBackground = Color.white.opacity(0.055)
    static let cardBackgroundElevated = Color.white.opacity(0.075)
    static let cardBackgroundSubtle = Color.white.opacity(0.035)
    static let cardBorder = Color.white.opacity(0.085)
    static let cardBorderStrong = Color.white.opacity(0.15)
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.72)
    static let textTertiary = Color.white.opacity(0.48)
    static let accent = Color(red: 0.42, green: 0.62, blue: 0.98)
    static let accentSoft = Color(red: 0.63, green: 0.76, blue: 0.98)
    static let accentBackground = accent.opacity(0.18)
    static let statusGreen = Color(red: 0.36, green: 0.82, blue: 0.62)
    static let statusOrange = Color(red: 0.96, green: 0.68, blue: 0.34)
    static let statusRed = Color(red: 0.96, green: 0.42, blue: 0.40)
    static let ringFiveHour = accent
    static let ringWeekly = statusGreen
    static let sparkDefault = accent.opacity(0.42)
    static let sparkHigh = statusOrange.opacity(0.48)
    static let sparkCritical = statusRed.opacity(0.5)
    static let inputBackground = Color.white.opacity(0.06)
    static let inputBorder = Color.white.opacity(0.09)
    static let inputBorderFocused = accent.opacity(0.72)
    static let toggleTrackOff = Color.white.opacity(0.18)
    static let toggleTrackOn = accent
    static let destructive = statusRed
    static let destructiveBackground = destructive.opacity(0.12)
    static let destructiveBorder = destructive.opacity(0.28)
    static let segmentedActiveBackground = accent.opacity(0.2)
    static let segmentedActiveBorder = accent.opacity(0.36)
    static let segmentedInactiveBackground = Color.white.opacity(0.035)
    static let segmentedTrackBackground = Color.white.opacity(0.028)
    static let sidebarSelectedBackground = accent.opacity(0.14)
    static let sidebarHoverBackground = Color.white.opacity(0.05)
    static let shadowColor = Color.black.opacity(0.32)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardHighlightGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.09), Color.white.opacity(0.01)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Spacing {
        static let containerPadding: CGFloat = DashboardTokens.scaled(18)
        static let contentPadding: CGFloat = DashboardTokens.scaled(20)
        static let cardPadding: CGFloat = DashboardTokens.scaled(16)
        static let compactCardPadding: CGFloat = DashboardTokens.scaled(12)
        static let cardRadius: CGFloat = DashboardTokens.scaled(16)
        static let controlRadius: CGFloat = DashboardTokens.scaled(12)
        static let smallRadius: CGFloat = DashboardTokens.scaled(10)
        static let cardGap: CGFloat = DashboardTokens.scaled(12)
        static let sectionSpacing: CGFloat = DashboardTokens.scaled(14)
        static let rowGap: CGFloat = DashboardTokens.scaled(6)
        static let rowHPadding: CGFloat = DashboardTokens.scaled(14)
        static let rowVPadding: CGFloat = DashboardTokens.scaled(13)
        static let rowRadius: CGFloat = DashboardTokens.scaled(15)
        static let ringSize: CGFloat = DashboardTokens.scaled(64)
        static let dotSize: CGFloat = DashboardTokens.scaled(8)
        static let sparkHeight: CGFloat = DashboardTokens.scaled(26)
        static let footerSpacing: CGFloat = DashboardTokens.scaled(10)
        static let heroPadding: CGFloat = DashboardTokens.scaled(18)
    }

    enum Font {
        static func sectionLabel() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(11), weight: .semibold)
        }

        static func cardHeading() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(15), weight: .semibold)
        }

        static func detailTitle() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(22), weight: .semibold)
        }

        static func heroTitle() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(28), weight: .bold)
        }

        static func accountName() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(14), weight: .semibold)
        }

        static func metadata() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(12), weight: .regular)
        }

        static func ringLabel() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(13), weight: .semibold)
        }

        static func statValue() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(22), weight: .semibold)
        }

        static func button() -> SwiftUI.Font {
            .system(size: DashboardTokens.scaled(12), weight: .semibold)
        }
    }

    enum Motion {
        static func hover(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.16)
        }

        static func emphasis(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.22)
        }

        static func springPress(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.8)
        }

        static func progress(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.42)
        }
    }
}
