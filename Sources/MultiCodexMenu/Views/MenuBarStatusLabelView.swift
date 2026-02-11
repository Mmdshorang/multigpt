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
            return .orange
        }
        if severityFraction >= 0.95 {
            return .red
        }
        if severityFraction >= 0.8 {
            return .orange
        }
        return .secondary
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbolName)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Circle()
                .fill(indicatorColor)
                .frame(width: 5, height: 5)
                .overlay(
                    Circle()
                        .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                )
                .offset(x: 1, y: 1)
        }
        .frame(width: 18, height: 14)
    }
}
