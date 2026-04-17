import SwiftUI

struct DashboardAccountRow: View {
    let row: AccountRowState
    let isExpanded: Bool
    let fiveHourProgressValue: Double
    let weeklyProgressValue: Double
    let isBusy: Bool
    let isSwitching: Bool
    let isAuthRunning: Bool
    let onActivate: () -> Void
    let onRowTap: () -> Void
    let onToggleExpanded: () -> Void
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

    private var primaryPercent: Double {
        max(fiveHourProgressValue, weeklyProgressValue)
    }

    private var progressColor: Color {
        switch UsageLevel.from(usedPercent: primaryPercent * 100) {
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
            return "circle"
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
            if isActivationHovered {
                return DashboardTokens.accentBackground.opacity(0.62)
            }
            return isRowHovered ? DashboardTokens.accentBackground.opacity(0.32) : Color.white.opacity(0.03)
        case .relogin:
            return DashboardTokens.statusOrange.opacity(0.2)
        case .none:
            return DashboardTokens.accentBackground.opacity(0.78)
        }
    }

    private var activationBorderColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            if isActivationHovered || isRowHovered {
                return DashboardTokens.accent.opacity(0.58)
            }
            return Color.white.opacity(0.16)
        case .relogin:
            return DashboardTokens.statusOrange.opacity(0.72)
        case .none:
            return DashboardTokens.accent.opacity(0.62)
        }
    }

    private var rowBackgroundColor: Color {
        if row.isCurrent {
            return DashboardTokens.accentBackground.opacity(isRowHovered ? 0.5 : 0.34)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(isRowHovered ? 0.16 : 0.1)
        }
        return Color.white.opacity(isRowHovered ? 0.06 : 0.02)
    }

    private var rowBorderColor: Color {
        if row.isCurrent {
            return DashboardTokens.accent.opacity(isRowHovered ? 0.56 : 0.36)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(isRowHovered ? 0.65 : 0.45)
        }
        return isRowHovered ? DashboardTokens.accent.opacity(0.24) : DashboardTokens.cardBorder
    }

    private var primaryAreaHelpText: String {
        switch row.primaryAction {
        case .switchAccount:
            return "Click row to expand details. Use checkbox to switch account"
        case .relogin:
            return "Click row to expand details. Use checkbox to re-login account"
        case .none:
            return "Current account. Click row or chevron to show usage details"
        }
    }

    private var chevronForegroundColor: Color {
        isExpanded ? DashboardTokens.textPrimary : DashboardTokens.textSecondary
    }

    private var chevronBackgroundColor: Color {
        isExpanded ? Color.white.opacity(0.1) : Color.white.opacity(0.04)
    }

    private var chevronBorderColor: Color {
        isExpanded ? DashboardTokens.accent.opacity(0.36) : DashboardTokens.cardBorder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                activationCheckboxButton

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.name)
                                .font(DashboardTokens.Font.accountName())
                                .foregroundStyle(DashboardTokens.textPrimary)
                                .lineLimit(1)

                            if row.isCurrent {
                                Text("CURRENT")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(DashboardTokens.accent)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(DashboardTokens.accentBackground, in: Capsule())
                            }
                        }

                        HStack(spacing: 6) {
                            Text("5h \(row.fiveHourPercent)")
                            Text("wk \(row.weeklyPercent)")
                        }
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                    }

                    Spacer(minLength: 8)

                    inlineMicroBar
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onRowTap)
                .help(primaryAreaHelpText)

                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(chevronForegroundColor)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(chevronBackgroundColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(chevronBorderColor, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(isExpanded ? "Collapse account details" : "Expand account details")
            }

            if isExpanded {
                expandedContent
                    .padding(.top, 8)
                    .transition(.opacity)
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
        .onHover { isRowHovered = $0 }
        .animation(.easeInOut(duration: 0.14), value: isRowHovered)
    }

    private var activationCheckboxButton: some View {
        Button(action: onActivate) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(activationBackgroundColor)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(activationBorderColor, lineWidth: 1)

                if isPrimaryActionInProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DashboardTokens.accent)
                } else {
                    Image(systemName: activationSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(activationForegroundColor)
                }
            }
            .frame(width: 30, height: 30)
            .scaleEffect((isActivationHovered && !isActivationDisabled) ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isActivationDisabled)
        .opacity(isActivationDisabled ? 0.52 : 1)
        .help(activationHelpText + " (only this checkbox activates account)")
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isActivationHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isActivationHovered)
    }

    private var inlineMicroBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.06))

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(progressColor)
                    .frame(width: geo.size.width * CGFloat(min(1, primaryPercent)))
            }
        }
        .frame(width: 48, height: 4)
    }

    private var expandedContent: some View {
        HStack(spacing: DashboardTokens.Spacing.cardGap) {
            DashboardProgressRing(
                progress: fiveHourProgressValue,
                color: DashboardTokens.ringFiveHour,
                label: "5H",
                valueText: row.fiveHourPercent
            )

            DashboardProgressRing(
                progress: weeklyProgressValue,
                color: DashboardTokens.ringWeekly,
                label: "WEEK",
                valueText: row.weeklyPercent
            )

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(row.resetText)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)

                if let email = row.workspaceEmailHint {
                    Text(email)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
