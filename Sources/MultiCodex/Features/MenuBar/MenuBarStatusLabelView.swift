import SwiftUI

struct MenuBarStatusLabelView: View {
    let title: String
    let symbolName: String
    let fiveHourFraction: Double
    let weeklyFraction: Double
    let hasError: Bool

    var body: some View {
        TrayMinimalStatusIconView(
            symbolName: symbolName,
            fiveHourFraction: fiveHourFraction,
            weeklyFraction: weeklyFraction,
            hasError: hasError
        )
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let fiveHour = Int((max(0, min(1, fiveHourFraction)) * 100).rounded())
        let weekly = Int((max(0, min(1, weeklyFraction)) * 100).rounded())
        if hasError {
            return "Runtime issue detected. Five hour usage \(fiveHour) percent. Weekly usage \(weekly) percent."
        }
        return "Five hour usage \(fiveHour) percent. Weekly usage \(weekly) percent."
    }
}

private struct TrayMinimalStatusIconView: View {
    let symbolName: String
    let fiveHourFraction: Double
    let weeklyFraction: Double
    let hasError: Bool

    private var severityFraction: Double {
        max(fiveHourFraction, weeklyFraction)
    }

    private var indicatorColor: Color {
        if hasError {
            return DashboardTokens.statusOrange
        }
        switch UsageLevel.from(usedPercent: severityFraction * 100) {
        case .critical:
            return DashboardTokens.statusRed
        case .warning:
            return DashboardTokens.statusOrange
        case .normal:
            return DashboardTokens.accentSoft
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbolName)
                .font(DashboardTokens.Font.headline())
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Circle()
                .fill(indicatorColor)
                .frame(width: 5, height: 5)
                .overlay(
                    Circle()
                        .stroke(DashboardTokens.background, lineWidth: 1)
                )
                .offset(x: 1, y: 1)
        }
        .frame(width: 18, height: 16)
    }
}
