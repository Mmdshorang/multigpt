import SwiftUI

// ──────────────────────────────────────────────
// Design Tokens — MultiCodex
// ──────────────────────────────────────────────
// Principles:
//   • No global scale factor — every size is intentional
//   • Calmer, more sophisticated accent (not saturated purple)
//   • Strong typographic hierarchy
//   • Apple HIG-aligned spacing and sizing
// ──────────────────────────────────────────────

enum DashboardTokens {
    // MARK: - Surfaces

    // Legacy scaled() removed — all sizes are now intentional 1:1 values

    static let background = Color(red: 0.068, green: 0.072, blue: 0.090)
    static let backgroundElevated = Color(red: 0.094, green: 0.098, blue: 0.118)
    static let backgroundTop = Color(red: 0.082, green: 0.086, blue: 0.108)
    static let backgroundBottom = Color(red: 0.056, green: 0.058, blue: 0.076)

    static let cardBackground = Color.white.opacity(0.042)
    static let cardBackgroundElevated = Color.white.opacity(0.058)
    static let cardBackgroundSubtle = Color.white.opacity(0.028)

    static let cardBorder = Color.white.opacity(0.078)
    static let cardBorderStrong = Color.white.opacity(0.14)

    // MARK: - Text

    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    // MARK: - Accent — Calm Blue-Violet

    static let accent = Color(red: 0.52, green: 0.52, blue: 0.94)
    static let accentSoft = Color(red: 0.62, green: 0.62, blue: 0.96)
    static let accentBackground = accent.opacity(0.14)

    // MARK: - Status

    static let statusGreen = Color(red: 0.30, green: 0.80, blue: 0.54)
    static let statusOrange = Color(red: 0.94, green: 0.60, blue: 0.30)
    static let statusRed = Color(red: 0.90, green: 0.34, blue: 0.34)

    // MARK: - Ring / Spark

    static let ringFiveHour = accent
    static let ringWeekly = accentSoft

    static let sparkDefault = accent.opacity(0.44)
    static let sparkHigh = statusOrange.opacity(0.50)
    static let sparkCritical = statusRed.opacity(0.52)

    // MARK: - Inputs

    static let inputBackground = Color.white.opacity(0.050)
    static let inputBorder = Color.white.opacity(0.086)
    static let inputBorderFocused = accent.opacity(0.54)

    // MARK: - Toggles

    static let toggleTrackOff = Color.white.opacity(0.14)
    static let toggleTrackOn = accent

    // MARK: - Destructive

    static let destructive = statusRed
    static let destructiveBackground = destructive.opacity(0.12)
    static let destructiveBorder = destructive.opacity(0.28)

    // MARK: - Segmented

    static let segmentedActiveBackground = accent.opacity(0.16)
    static let segmentedActiveBorder = accent.opacity(0.34)
    static let segmentedInactiveBackground = Color.white.opacity(0.0)
    static let segmentedTrackBackground = Color.white.opacity(0.040)

    // MARK: - Sidebar

    static let sidebarSelectedBackground = accent.opacity(0.12)
    static let sidebarHoverBackground = Color.white.opacity(0.044)

    // MARK: - Shadow

    static let shadowColor = Color.black.opacity(0.30)

    // MARK: - Gradients

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardHighlightGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(0.070), Color.white.opacity(0.010)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Spacing

    enum Spacing {
        // Container
        static let containerPadding: CGFloat = 14

        // Content
        static let contentPadding: CGFloat = 18

        // Cards
        static let cardPadding: CGFloat = 12
        static let compactCardPadding: CGFloat = 10
        static let cardRadius: CGFloat = 12
        static let controlRadius: CGFloat = 9
        static let smallRadius: CGFloat = 7

        // Layout
        static let cardGap: CGFloat = 8
        static let sectionSpacing: CGFloat = 10
        static let rowGap: CGFloat = 4

        // Rows
        static let rowHPadding: CGFloat = 10
        static let rowVPadding: CGFloat = 9
        static let rowRadius: CGFloat = 10

        // Components
        static let ringSize: CGFloat = 48
        static let dotSize: CGFloat = 6
        static let sparkHeight: CGFloat = 22
        static let footerSpacing: CGFloat = 7
        static let heroPadding: CGFloat = 14
    }

    // MARK: - Typography
    //
    // Size ladder (pt):
    //   22  heroTitle       bold       — empty state headings
    //   18  detailTitle     semibold   — settings page hero titles
    //   15  title           semibold   — app name in header / sidebar
    //   14  headline        semibold   — icon overlays, large labels
    //   13  cardHeading     semibold   — card section titles, usage value
    //   12  bodySemibold    semibold   — sidebar row selected, metric value
    //   12  bodyMedium      medium     — sidebar row unselected
    //   12  bodyRegular     regular    — sidebar subtitle
    //   12  monospaced      semibold   — keyboard shortcut keys
    //   11  metadata        regular    — descriptions, secondary text
    //   11  metadataBold    semibold   — metric labels, status text
    //   11  formLabel       medium     — form row icons
    //   10  sectionLabel    medium     — section headers, labels
    //   10  caption         semibold   — badges, tiny labels, status
    //   10  captionRegular  regular    — sidebar selected subtitle
    //    9  microLabel      semibold   — chevrons, sort menu checkmark, status dot label
    //    7  chevron         semibold   — expand/collapse chevrons

    enum Font {
        // Titles
        static func heroTitle() -> SwiftUI.Font     { .system(size: 22, weight: .bold) }
        static func detailTitle() -> SwiftUI.Font   { .system(size: 18, weight: .semibold) }
        static func title() -> SwiftUI.Font         { .system(size: 15, weight: .semibold) }
        static func headline() -> SwiftUI.Font      { .system(size: 14, weight: .semibold) }

        // Body
        static func cardHeading() -> SwiftUI.Font   { .system(size: 13, weight: .semibold) }
        static func bodySemibold() -> SwiftUI.Font  { .system(size: 12, weight: .semibold) }
        static func bodyMedium() -> SwiftUI.Font    { .system(size: 12, weight: .medium) }
        static func bodyRegular() -> SwiftUI.Font   { .system(size: 12, weight: .regular) }
        static func monospaced() -> SwiftUI.Font    { .system(size: 12, weight: .semibold, design: .monospaced) }

        // Small
        static func metadata() -> SwiftUI.Font      { .system(size: 11, weight: .regular) }
        static func metadataBold() -> SwiftUI.Font  { .system(size: 11, weight: .semibold) }
        static func formLabel() -> SwiftUI.Font     { .system(size: 11, weight: .medium) }
        static func sectionLabel() -> SwiftUI.Font  { .system(size: 10, weight: .medium) }
        static func caption() -> SwiftUI.Font       { .system(size: 10, weight: .semibold) }
        static func captionRegular() -> SwiftUI.Font { .system(size: 10, weight: .regular) }
        static func microLabel() -> SwiftUI.Font    { .system(size: 9, weight: .semibold) }

        // Icons / Decorative
        static func chevron() -> SwiftUI.Font       { .system(size: 7, weight: .semibold) }

        // Semantic aliases (keep existing call sites working)
        static func accountName() -> SwiftUI.Font   { bodySemibold() }
        static func ringLabel() -> SwiftUI.Font     { metadataBold() }
        static func statValue() -> SwiftUI.Font     { detailTitle() }
        static func button() -> SwiftUI.Font        { metadataBold() }
    }

    // MARK: - Motion

    enum Motion {
        static func hover(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.15)
        }

        static func emphasis(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.20)
        }

        static func disclosure(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.08)
        }

        static func springPress(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78)
        }

        static func progress(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.38)
        }
    }
}
