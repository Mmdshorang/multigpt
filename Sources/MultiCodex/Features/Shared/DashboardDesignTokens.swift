import SwiftUI

enum DashboardTokens {
    static let background = Color(red: 0.047, green: 0.055, blue: 0.078)
    static let cardBackground = Color.white.opacity(0.03)
    static let cardBorder = Color.white.opacity(0.06)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.30)
    static let accent = Color(red: 0.388, green: 0.400, blue: 0.945)
    static let accentBackground = accent.opacity(0.12)
    static let statusGreen = Color(red: 0.204, green: 0.827, blue: 0.600)
    static let statusOrange = Color(red: 0.984, green: 0.576, blue: 0.235)
    static let statusRed = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let ringFiveHour = accent
    static let ringWeekly = statusGreen
    static let sparkDefault = accent.opacity(0.4)
    static let sparkHigh = statusOrange.opacity(0.5)
    static let sparkCritical = statusRed.opacity(0.5)

    enum Spacing {
        static let containerPadding: CGFloat = 16
        static let cardPadding: CGFloat = 12
        static let cardRadius: CGFloat = 10
        static let cardGap: CGFloat = 8
        static let sectionSpacing: CGFloat = 10
        static let rowGap: CGFloat = 4
        static let rowHPadding: CGFloat = 10
        static let rowVPadding: CGFloat = 8
        static let rowRadius: CGFloat = 8
        static let ringSize: CGFloat = 48
        static let dotSize: CGFloat = 8
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
            .system(size: 18, weight: .bold)
        }

        static func accountName() -> SwiftUI.Font {
            .system(size: 12, weight: .semibold)
        }

        static func metadata() -> SwiftUI.Font {
            .system(size: 10, weight: .regular)
        }

        static func ringLabel() -> SwiftUI.Font {
            .system(size: 10, weight: .semibold)
        }

        static func button() -> SwiftUI.Font {
            .system(size: 11, weight: .regular)
        }
    }
}
