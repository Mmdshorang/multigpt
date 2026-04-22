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
            return DashboardTokens.textSecondary
        case .relogin:
            return DashboardTokens.statusOrange
        case .none:
            return DashboardTokens.accent
        }
    }

    private var activationBackgroundColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            return DashboardTokens.cardBackgroundSubtle
        case .relogin:
            return DashboardTokens.statusOrange.opacity(0.18)
        case .none:
            return DashboardTokens.accentBackground.opacity(0.9)
        }
    }

    private var activationBorderColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            return DashboardTokens.cardBorder
        case .relogin:
            return DashboardTokens.statusOrange.opacity(0.52)
        case .none:
            return DashboardTokens.accent.opacity(0.4)
        }
    }

    private var rowBackgroundColor: Color {
        if row.isCurrent {
            return DashboardTokens.accentBackground.opacity(0.44)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(0.10)
        }
        return DashboardTokens.cardBackgroundSubtle
    }

    private var rowBorderColor: Color {
        if row.isCurrent {
            return DashboardTokens.accent.opacity(0.3)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(0.24)
        }
        return DashboardTokens.cardBorder
    }

    private var statusColor: Color {
        switch row.account.connectionState {
        case .connected:
            return DashboardTokens.accentSoft
        case .needsLogin:
            return DashboardTokens.statusOrange
        case .error:
            return DashboardTokens.statusRed
        }
    }

    private var connectionLabel: String? {
        if row.isCurrent {
            return "Current"
        }

        switch row.primaryAction {
        case .relogin:
            return "Needs Login"
        case .switchAccount:
            return nil
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

                                if let connectionLabel {
                                    AccountStatusPill(
                                        text: connectionLabel,
                                        color: row.isCurrent ? DashboardTokens.accent : statusColor
                                    )
                                }
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
                .help(primaryAreaHelpText)
            }

            if isExpanded {
                expandedContent
                    .padding(.top, DashboardTokens.scaled(14))
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                        )
                    )
            }
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
        .onTapGesture {
            withAnimation(DashboardTokens.Motion.emphasis(reduceMotion: reduceMotion)) {
                onRowTap()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Use the primary action button to switch or re-login. Use row action to expand details.")
        .accessibilityAction(named: Text(isExpanded ? "Collapse details" : "Expand details")) {
            withAnimation(DashboardTokens.Motion.emphasis(reduceMotion: reduceMotion)) {
                onToggleExpanded()
            }
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
        }
        .buttonStyle(.plain)
        .disabled(isActivationDisabled)
        .opacity(isActivationDisabled ? 0.52 : 1)
        .accessibilityLabel(activationHelpText)
        .accessibilityValue(isPrimaryActionInProgress ? "In progress" : "Ready")
        .help(activationHelpText)
        .contentShape(Circle())
    }

    private var inlineMicroBar: some View {
        let barWidth = DashboardTokens.scaled(70)
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.08))

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(progressColor)
                .frame(width: barWidth * CGFloat(compactProgressFraction))
        }
        .frame(width: barWidth, height: DashboardTokens.scaled(5))
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

            let barWidth = DashboardTokens.scaled(144)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color)
                    .frame(width: barWidth * CGFloat(min(1, max(0, progress))))
            }
            .frame(width: barWidth, height: DashboardTokens.scaled(5))
        }
    }
}
