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

    // MARK: - Derived State

    private var isPrimaryActionInProgress: Bool {
        switch row.primaryAction {
        case .switchAccount: return isSwitching
        case .relogin: return isAuthRunning
        case .none: return false
        }
    }

    private var compactProgressFraction: Double {
        min(1, max(0, compactProgressValue))
    }

    private var progressColor: Color {
        switch UsageLevel.from(usedPercent: compactUsedPercent) {
        case .critical: return DashboardTokens.statusRed
        case .warning: return DashboardTokens.statusOrange
        case .normal: return DashboardTokens.accent
        }
    }

    private var activationHelpText: String {
        switch row.primaryAction {
        case .switchAccount: return "Switch to this account"
        case .relogin: return "Re-login this account"
        case .none: return "Current account"
        }
    }

    private var activationSymbol: String {
        switch row.primaryAction {
        case .switchAccount: return "arrow.left.arrow.right.circle.fill"
        case .relogin: return "arrow.triangle.2.circlepath.circle.fill"
        case .none: return "checkmark.circle.fill"
        }
    }

    private var isActivationDisabled: Bool {
        isBusy && row.primaryAction != .none
    }

    private var activationForegroundColor: Color {
        switch row.primaryAction {
        case .switchAccount: return DashboardTokens.textSecondary
        case .relogin: return DashboardTokens.statusOrange
        case .none: return DashboardTokens.accent
        }
    }

    private var activationBackgroundColor: Color {
        switch row.primaryAction {
        case .switchAccount: return DashboardTokens.cardBackgroundSubtle
        case .relogin: return DashboardTokens.statusOrange.opacity(0.14)
        case .none: return DashboardTokens.accentBackground.opacity(0.85)
        }
    }

    private var activationBorderColor: Color {
        switch row.primaryAction {
        case .switchAccount: return DashboardTokens.cardBorder
        case .relogin: return DashboardTokens.statusOrange.opacity(0.48)
        case .none: return DashboardTokens.accent.opacity(0.36)
        }
    }

    private var rowBackgroundColor: Color {
        if row.isCurrent {
            return DashboardTokens.accentBackground.opacity(0.40)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(0.08)
        }
        return DashboardTokens.cardBackgroundSubtle
    }

    private var rowBorderColor: Color {
        if row.isCurrent {
            return DashboardTokens.accent.opacity(0.26)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(0.20)
        }
        return DashboardTokens.cardBorder
    }

    private var statusColor: Color {
        switch row.account.connectionState {
        case .connected: return DashboardTokens.accentSoft
        case .needsLogin: return DashboardTokens.statusOrange
        case .error: return DashboardTokens.statusRed
        }
    }

    private var connectionLabel: String? {
        if row.isCurrent { return "Current" }
        switch row.primaryAction {
        case .relogin: return "Needs Login"
        case .switchAccount: return nil
        case .none: return row.account.connectionState.label
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Collapsed Row ──
            HStack(spacing: 10) {
                activationCheckboxButton

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
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

                    VStack(alignment: .trailing, spacing: 5) {
                        Text("5h \(fiveHourPercentText) \u{2022} Wk \(weeklyPercentText)")
                            .font(DashboardTokens.Font.metadata().weight(.semibold))
                            .foregroundStyle(DashboardTokens.textPrimary)
                            .monospacedDigit()

                        inlineMicroBar
                    }

                    Image(systemName: "chevron.down")
                        .font(DashboardTokens.Font.chevron())
                        .foregroundStyle(DashboardTokens.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion), value: isExpanded)
                }
                .contentShape(Rectangle())
                .help(primaryAreaHelpText)
            }

            // ── Expanded Detail ──
            if isExpanded {
                expandedContent
                    .padding(.top, 12)
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

    // MARK: - Activation Button

    private var primaryAreaHelpText: String {
        switch row.primaryAction {
        case .switchAccount:
            return "Tap to expand. Use the leading button to switch."
        case .relogin:
            return "Tap to expand. Use the leading button to re-login."
        case .none:
            return "Current account. Tap to show usage details."
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
                        .font(DashboardTokens.Font.caption())
                        .foregroundStyle(activationForegroundColor)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(isActivationDisabled)
        .opacity(isActivationDisabled ? 0.48 : 1)
        .accessibilityLabel(activationHelpText)
        .accessibilityValue(isPrimaryActionInProgress ? "In progress" : "Ready")
        .help(activationHelpText)
        .contentShape(Circle())
    }

    // MARK: - Inline Micro Bar

    private var inlineMicroBar: some View {
        let barWidth: CGFloat = 58
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.07))

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(progressColor)
                .frame(width: barWidth * CGFloat(compactProgressFraction))
        }
        .frame(width: barWidth, height: 3.5)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
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

            VStack(alignment: .trailing, spacing: 4) {
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(DashboardTokens.Font.caption())
                    .tracking(0.5)
                    .foregroundStyle(DashboardTokens.textTertiary)
                Text(valueText)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)
                    .monospacedDigit()
            }

            let barWidth: CGFloat = 118
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.07))

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: barWidth * CGFloat(min(1, max(0, progress))))
            }
            .frame(width: barWidth, height: 3.5)
        }
    }
}
