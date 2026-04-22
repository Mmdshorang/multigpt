import SwiftUI

struct DashboardAccountRow: View {
    let row: AccountRowState
    let isExpanded: Bool
    let fiveHourProgressValue: Double
    let weeklyProgressValue: Double
    let fiveHourPercentText: String
    let weeklyPercentText: String
    let compactProgressValue: Double
    let compactUsedPercent: Double?
    let isBusy: Bool
    let isSwitching: Bool
    let isAuthRunning: Bool
    let onActivate: () -> Void
    let onRowTap: () -> Void
    let onToggleExpanded: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isActivationHovered = false
    @State private var isRowHovered = false

    private var isPrimaryActionInProgress: Bool {
        switch row.primaryAction {
        case .switchAccount:
            return isSwitching
        case .relogin:
            return isAuthRunning
        case .none:
            return false
        }
    }

    private var compactProgressFraction: Double {
        min(1, max(0, compactProgressValue))
    }

    private var progressColor: Color {
        switch UsageLevel.from(usedPercent: compactUsedPercent) {
        case .critical:
            return DashboardTokens.statusRed
        case .warning:
            return DashboardTokens.statusOrange
        case .normal:
            return DashboardTokens.accent
        }
    }

    private var activationHelpText: String {
        switch row.primaryAction {
        case .switchAccount:
            return "Switch to this account"
        case .relogin:
            return "Re-login this account"
        case .none:
            return "Current account"
        }
    }

    private var activationSymbol: String {
        switch row.primaryAction {
        case .switchAccount:
            return "arrow.left.arrow.right.circle.fill"
        case .relogin:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .none:
            return "checkmark.circle.fill"
        }
    }

    private var isActivationDisabled: Bool {
        isBusy && row.primaryAction != .none
    }

    private var activationForegroundColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            return (isActivationHovered || isRowHovered) ? DashboardTokens.accent : DashboardTokens.textSecondary
        case .relogin:
            return DashboardTokens.statusOrange
        case .none:
            return DashboardTokens.accent
        }
    }

    private var activationBackgroundColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            return isActivationHovered ? DashboardTokens.accentBackground.opacity(0.72) : DashboardTokens.cardBackgroundSubtle
        case .relogin:
            return DashboardTokens.statusOrange.opacity(0.18)
        case .none:
            return DashboardTokens.accentBackground.opacity(0.9)
        }
    }

    private var activationBorderColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            return isActivationHovered ? DashboardTokens.accent.opacity(0.58) : DashboardTokens.cardBorder
        case .relogin:
            return DashboardTokens.statusOrange.opacity(0.52)
        case .none:
            return DashboardTokens.accent.opacity(0.4)
        }
    }

    private var rowBackgroundColor: Color {
        if row.isCurrent {
            return DashboardTokens.accentBackground.opacity(isRowHovered ? 0.58 : 0.44)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(isRowHovered ? 0.14 : 0.10)
        }
        return isRowHovered ? DashboardTokens.cardBackgroundElevated : DashboardTokens.cardBackgroundSubtle
    }

    private var rowBorderColor: Color {
        if row.isCurrent {
            return DashboardTokens.accent.opacity(isRowHovered ? 0.46 : 0.3)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(isRowHovered ? 0.42 : 0.24)
        }
        return isRowHovered ? DashboardTokens.cardBorderStrong : DashboardTokens.cardBorder
    }

    private var statusColor: Color {
        switch row.account.connectionState {
        case .connected:
            return DashboardTokens.statusGreen
        case .needsLogin:
            return DashboardTokens.statusOrange
        case .error:
            return DashboardTokens.statusRed
        }
    }

    private var connectionLabel: String {
        if row.isCurrent {
            return "Current"
        }

        switch row.primaryAction {
        case .relogin:
            return "Needs Login"
        case .switchAccount:
            return "Available"
        case .none:
            return row.account.connectionState.label
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                activationCheckboxButton

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(row.name)
                                .font(DashboardTokens.Font.accountName())
                                .foregroundStyle(DashboardTokens.textPrimary)
                                .lineLimit(1)

                            AccountStatusPill(
                                text: connectionLabel,
                                color: row.isCurrent ? DashboardTokens.accent : statusColor
                            )
                        }

                        Text(row.workspaceEmailHint ?? row.resetText)
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("5h \(fiveHourPercentText) • Week \(weeklyPercentText)")
                                .font(DashboardTokens.Font.metadata().weight(.semibold))
                                .foregroundStyle(DashboardTokens.textPrimary)
                                .monospacedDigit()

                            inlineMicroBar
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: DashboardTokens.scaled(9), weight: .semibold))
                            .foregroundStyle(DashboardTokens.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onRowTap)
                .help(primaryAreaHelpText)
            }

            expandedContent
                .padding(.top, isExpanded ? 14 : 0)
                .frame(height: isExpanded ? nil : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .animation(DashboardTokens.Motion.emphasis(reduceMotion: reduceMotion), value: isExpanded)
        }
        .padding(.horizontal, DashboardTokens.Spacing.rowHPadding)
        .padding(.vertical, DashboardTokens.Spacing.rowVPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.rowRadius, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.rowRadius, style: .continuous)
                .stroke(rowBorderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DashboardTokens.Spacing.rowRadius, style: .continuous))
        .onHover { isRowHovered = $0 }
        .animation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion), value: isRowHovered)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Use the primary action button to switch or re-login. Use row action to expand details.")
        .accessibilityAction(named: Text(isExpanded ? "Collapse details" : "Expand details")) {
            onToggleExpanded()
        }
    }

    private var primaryAreaHelpText: String {
        switch row.primaryAction {
        case .switchAccount:
            return "Click row to expand details. Use the leading button to switch accounts quickly."
        case .relogin:
            return "Click row to expand details. Use the leading button to start a fresh login."
        case .none:
            return "Current account. Click row to show usage details."
        }
    }

    private var activationCheckboxButton: some View {
        Button(action: onActivate) {
            ZStack {
                Circle()
                    .fill(activationBackgroundColor)
                Circle()
                    .stroke(activationBorderColor, lineWidth: 1)

                if isPrimaryActionInProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DashboardTokens.accent)
                } else {
                    Image(systemName: activationSymbol)
                        .font(.system(size: DashboardTokens.scaled(12), weight: .semibold))
                        .foregroundStyle(activationForegroundColor)
                }
            }
            .frame(width: DashboardTokens.scaled(28), height: DashboardTokens.scaled(28))
            .scaleEffect((isActivationHovered && !isActivationDisabled) ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isActivationDisabled)
        .opacity(isActivationDisabled ? 0.52 : 1)
        .accessibilityLabel(activationHelpText)
        .accessibilityValue(isPrimaryActionInProgress ? "In progress" : "Ready")
        .help(activationHelpText)
        .contentShape(Circle())
        .onHover { isActivationHovered = $0 }
        .animation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion), value: isActivationHovered)
    }

    private var inlineMicroBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(progressColor)
                    .frame(width: geo.size.width * CGFloat(compactProgressFraction))
            }
        }
        .frame(width: DashboardTokens.scaled(70), height: DashboardTokens.scaled(5))
    }

    private var expandedContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                expandedMetricBar(
                    label: "5H",
                    valueText: fiveHourPercentText,
                    progress: fiveHourProgressValue,
                    color: DashboardTokens.ringFiveHour
                )
                expandedMetricBar(
                    label: "WEEK",
                    valueText: weeklyPercentText,
                    progress: weeklyProgressValue,
                    color: DashboardTokens.ringWeekly
                )
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(row.resetText)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .multilineTextAlignment(.trailing)

                if let email = row.workspaceEmailHint {
                    Text(email)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func expandedMetricBar(
        label: String,
        valueText: String,
        progress: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: DashboardTokens.scaled(9), weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(DashboardTokens.textTertiary)
                Text(valueText)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, progress))))
                }
            }
            .frame(width: DashboardTokens.scaled(144), height: DashboardTokens.scaled(5))
        }
    }
}
