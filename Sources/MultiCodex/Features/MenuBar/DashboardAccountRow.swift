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
            return "Activate account"
        case .relogin:
            return "Re-login to activate"
        case .none:
            return "Current account"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    activationCheckboxButton

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
        ZStack {
            if isPrimaryActionInProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(DashboardTokens.accent)
            } else {
                Button(action: onActivate) {
                    Image(systemName: row.primaryAction == .none ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(row.primaryAction == .none ? DashboardTokens.accent : DashboardTokens.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isBusy && row.primaryAction != .none)
                .opacity((isBusy && row.primaryAction != .none) ? 0.5 : 1)
                .help(activationHelpText)
            }
        }
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
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
