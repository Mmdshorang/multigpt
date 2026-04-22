import SwiftUI

struct RuntimeStatusPresentation {
    let text: String
    let symbol: String
    let color: Color
}

enum AccountPresentation {
    static func statusColor(for state: AccountConnectionState) -> Color {
        switch state {
        case .connected:
            return DashboardTokens.accentSoft
        case .needsLogin:
            return DashboardTokens.statusOrange
        case .error:
            return DashboardTokens.statusRed
        }
    }

    static func alertColor(for severity: MenuAlertState.Severity) -> Color {
        switch severity {
        case .runtimeUnavailable:
            return DashboardTokens.statusOrange
        case .refreshError:
            return DashboardTokens.statusRed
        case .authRequired:
            return DashboardTokens.statusOrange
        }
    }

    static func alertSymbol(for severity: MenuAlertState.Severity) -> String {
        switch severity {
        case .runtimeUnavailable:
            return "terminal"
        case .refreshError:
            return "exclamationmark.triangle.fill"
        case .authRequired:
            return "person.crop.circle.badge.exclamationmark"
        }
    }

    static func runtimeStatus(summary: String?, isAvailable: Bool) -> RuntimeStatusPresentation {
        if isAvailable {
            return RuntimeStatusPresentation(
                text: summary ?? "Codex runtime is available.",
                symbol: "checkmark.circle.fill",
                color: DashboardTokens.accentSoft
            )
        }

        if let summary {
            return RuntimeStatusPresentation(
                text: summary,
                symbol: "exclamationmark.triangle.fill",
                color: DashboardTokens.statusOrange
            )
        }

        return RuntimeStatusPresentation(
            text: "Checking Codex runtime...",
            symbol: "clock",
            color: DashboardTokens.textSecondary
        )
    }
}

struct AccountStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: DashboardTokens.scaled(9), weight: .semibold))
            .tracking(0.3)
            .padding(.horizontal, DashboardTokens.scaled(7))
            .padding(.vertical, DashboardTokens.scaled(3))
            .background(
                Capsule()
                    .fill(color.opacity(0.14))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .foregroundStyle(color)
    }
}

struct SubtleWarningRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(DashboardTokens.statusOrange)
                .padding(.top, 1)

            Text(text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DashboardTokens.scaled(10))
        .padding(.vertical, DashboardTokens.scaled(8))
        .background(
            DashboardTokens.statusOrange.opacity(0.1),
            in: RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(DashboardTokens.statusOrange.opacity(0.16), lineWidth: 1)
        )
    }
}

struct AccountUsageMetricCard: View {
    let title: String
    let metric: UsageMetric
    let resetDisplayMode: ResetDisplayMode
    let progressValue: Double
    let valueText: String

    private var tone: Color {
        switch UsageLevel.from(usedPercent: metric.usedPercent) {
        case .critical:
            return DashboardTokens.statusRed
        case .warning:
            return DashboardTokens.statusOrange
        case .normal:
            return DashboardTokens.accentSoft
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                DashboardSectionHeader(title: title)
                Spacer()
                Text(valueText)
                    .font(DashboardTokens.Font.cardHeading())
                    .foregroundStyle(DashboardTokens.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(tone)
                        .frame(width: geo.size.width * CGFloat(min(1, progressValue)))
                }
            }
            .frame(height: DashboardTokens.scaled(6))

            Text(metric.resetText(mode: resetDisplayMode))
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(fill: DashboardTokens.cardBackgroundSubtle)
    }
}
