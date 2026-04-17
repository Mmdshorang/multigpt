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
            return "square"
        case .relogin:
            return "exclamationmark.square.fill"
        case .none:
            return "checkmark.square.fill"
        }
    }

    private var isActivationDisabled: Bool {
        isBusy && row.primaryAction != .none
    }

    private var activationForegroundColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            return isActivationHovered ? DashboardTokens.textPrimary : DashboardTokens.textSecondary
        case .relogin:
            return DashboardTokens.statusOrange
        case .none:
            return DashboardTokens.accent
        }
    }

    private var activationBackgroundColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            return isActivationHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.03)
        case .relogin:
            return DashboardTokens.statusOrange.opacity(0.14)
        case .none:
            return DashboardTokens.accentBackground
        }
    }

    private var activationBorderColor: Color {
        switch row.primaryAction {
        case .switchAccount:
            return isActivationHovered ? DashboardTokens.accent.opacity(0.34) : DashboardTokens.cardBorder
        case .relogin:
            return DashboardTokens.statusOrange.opacity(0.55)
        case .none:
            return DashboardTokens.accent.opacity(0.4)
        }
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

                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DashboardTokens.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            if isExpanded {
                expandedContent
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, DashboardTokens.Spacing.rowHPadding)
        .padding(.vertical, DashboardTokens.Spacing.rowVPadding)
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activationForegroundColor)
                }
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(isActivationDisabled)
        .opacity(isActivationDisabled ? 0.52 : 1)
        .help(activationHelpText)
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
