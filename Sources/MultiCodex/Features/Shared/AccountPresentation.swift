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
            return DashboardTokens.statusGreen
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
                text: summary ?? "codex runtime is available.",
                symbol: "checkmark.circle.fill",
                color: DashboardTokens.statusGreen
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
            text: "Checking codex runtime...",
            symbol: "clock",
            color: DashboardTokens.textSecondary
        )
    }
}

struct AccountStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.lowercased())
            .font(.system(size: 9, weight: .medium))
            .tracking(0.3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(color)
    }
}

struct SubtleWarningRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(DashboardTokens.statusOrange)
            Text(text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            DashboardTokens.statusOrange.opacity(0.1),
            in: RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
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
            return DashboardTokens.statusGreen
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(DashboardTokens.Font.sectionLabel())
                    .tracking(1.5)
                    .foregroundStyle(DashboardTokens.textTertiary)
                Spacer()
                Text(valueText)
                    .font(DashboardTokens.Font.cardHeading())
                    .foregroundStyle(DashboardTokens.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.06))

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(tone)
                        .frame(width: geo.size.width * CGFloat(min(1, progressValue)))
                }
            }
            .frame(height: 3)

            Text(metric.resetText(mode: resetDisplayMode))
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DashboardTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill(DashboardTokens.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }
}
