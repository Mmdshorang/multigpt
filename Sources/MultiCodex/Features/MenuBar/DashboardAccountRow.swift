import SwiftUI

struct DashboardAccountRow: View {
    let row: AccountRowState
    let isExpanded: Bool
    let fiveHourProgressValue: Double
    let weeklyProgressValue: Double
    let fiveHourPercentText: String
    let weeklyPercentText: String
    let isBusy: Bool
    let isSwitching: Bool
    let isAuthRunning: Bool
    let onActivate: () -> Void
    let onRowTap: () -> Void
    let onToggleExpanded: () -> Void
    @State private var disclosureProgress: CGFloat = 0
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Derived State

    private var isPrimaryActionInProgress: Bool {
        switch row.primaryAction {
        case .switchAccount: return isSwitching
        case .relogin: return isAuthRunning
        case .none: return false
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
            return DashboardTokens.accentBackground.opacity(isHovered ? 0.52 : 0.40)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(isHovered ? 0.12 : 0.08)
        }
        return isHovered ? DashboardTokens.hoverOverlay : DashboardTokens.cardBackgroundSubtle
    }

    private var rowBorderColor: Color {
        if row.isCurrent {
            return DashboardTokens.accent.opacity(isHovered ? 0.34 : 0.26)
        }
        if row.primaryAction == .relogin {
            return DashboardTokens.statusOrange.opacity(isHovered ? 0.28 : 0.20)
        }
        return isHovered ? DashboardTokens.hoverBorder : DashboardTokens.cardBorder
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

    /// Inline micro usage bar color for the 5h metric in collapsed state
    private var microBarColor: Color {
        if fiveHourProgressValue > 0.80 { return DashboardTokens.statusRed }
        if fiveHourProgressValue > 0.60 { return DashboardTokens.statusOrange }
        return DashboardTokens.accent
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

                        HStack(spacing: 6) {
                            Text(row.workspaceEmailHint ?? row.resetText)
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            // Inline micro usage bar (collapsed only)
                            if !isExpanded, row.account.connectionState == .connected {
                                microUsageBar
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(DashboardTokens.Font.chevron())
                        .foregroundStyle(DashboardTokens.textTertiary)
                        .rotationEffect(.degrees(180 * disclosureProgress))
                }
                .contentShape(Rectangle())
                .help(primaryAreaHelpText)
            }

            expandedDisclosure
        }
        .padding(.horizontal, DashboardTokens.Spacing.rowHPadding)
        .padding(.vertical, DashboardTokens.Spacing.rowVPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.rowRadius, style: .continuous)
                .fill(rowBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.rowRadius, style: .continuous)
                .stroke(rowBorderColor, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: DashboardTokens.Spacing.rowRadius, style: .continuous))
        .onHover { hovering in
            withAnimation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onRowTap()
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Use the primary action button to switch or re-login. Use row action to expand details.")
        .accessibilityAction(named: Text(isExpanded ? "Collapse details" : "Expand details")) {
            onToggleExpanded()
        }
        .onAppear {
            disclosureProgress = isExpanded ? 1 : 0
        }
        .onChange(of: isExpanded) { expanded in
            withAnimation(DashboardTokens.Motion.disclosure(reduceMotion: reduceMotion)) {
                disclosureProgress = expanded ? 1 : 0
            }
        }
    }

    // MARK: - Micro Usage Bar (collapsed inline)

    private var microUsageBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.06))

                Capsule()
                    .fill(microBarColor.opacity(0.72))
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fiveHourProgressValue))))
            }
        }
        .frame(width: 36, height: 3)
        .accessibilityLabel("5h usage")
        .accessibilityValue(fiveHourPercentText)
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
                    .stroke(activationBorderColor, lineWidth: 0.5)

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
            .shadow(
                color: row.primaryAction == .none ? DashboardTokens.accent.opacity(0.18) : .clear,
                radius: row.primaryAction == .none ? 4 : 0,
                y: 0
            )
        }
        .buttonStyle(.plain)
        .disabled(isActivationDisabled)
        .opacity(isActivationDisabled ? 0.48 : 1)
        .accessibilityLabel(activationHelpText)
        .accessibilityValue(isPrimaryActionInProgress ? "In progress" : "Ready")
        .help(activationHelpText)
        .contentShape(Circle())
    }

    // MARK: - Expanded Content

    private var expandedDisclosure: some View {
        Group {
            if isExpanded {
                expandedContent
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                expandedMetricBar(
                    label: "5H",
                    valueText: fiveHourPercentText,
                    resetText: row.resetText,
                    progress: fiveHourProgressValue,
                    color: DashboardTokens.ringFiveHour
                )
                expandedMetricBar(
                    label: "WEEK",
                    valueText: weeklyPercentText,
                    resetText: row.account.usage.weekly.resetText(mode: row.resetDisplayMode),
                    progress: weeklyProgressValue,
                    color: DashboardTokens.ringWeekly
                )
            }

            expandedDetailFooter
        }
    }

    private func expandedMetricBar(
        label: String,
        valueText: String,
        resetText: String,
        progress: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(label)
                    .font(DashboardTokens.Font.caption())
                    .tracking(0.5)
                    .foregroundStyle(DashboardTokens.textTertiary)
                Text(valueText)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)
                    .monospacedDigit()

                Spacer(minLength: 8)

                Text(resetText)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.70), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * CGFloat(min(1, max(0, progress))))
                        .shadow(color: color.opacity(0.30), radius: 3, y: 0)
                }
            }
            .frame(height: 4)
        }
    }

    private var expandedDetailFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let paceText = row.account.paceSummary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(paceColor(row.account.fiveHourPace?.stage))
                        .frame(width: 6, height: 6)
                    Text(paceText)
                        .font(DashboardTokens.Font.caption())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let email = row.workspaceEmailHint {
                    Label(email, systemImage: "person.crop.circle")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 6)

                if let cost = row.account.costReport, cost.totalCostUSD > 0 {
                    Label("\(cost.formattedToday) today", systemImage: "dollarsign.circle")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func paceColor(_ stage: UsagePace.Stage?) -> Color {
        guard let stage else { return DashboardTokens.textTertiary }
        switch stage {
        case .onTrack, .slightlyBehind, .behind, .farBehind:
            return DashboardTokens.accent
        case .slightlyAhead:
            return DashboardTokens.statusOrange
        case .ahead, .farAhead:
            return DashboardTokens.statusRed
        }
    }
}
