import SwiftUI

struct SequentialLoginTrackerView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            DashboardTokens.backgroundGradient
                .ignoresSafeArea()

            if let state = viewModel.sequentialLoginState {
                content(state: state)
            } else {
                emptyState
            }
        }
    }

    private func content(state: SequentialLoginState) -> some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(14)) {
            SettingsPanelCard(fill: DashboardTokens.cardBackground) {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(14)) {
                    HStack(alignment: .top, spacing: DashboardTokens.scaled(12)) {
                        trackerSectionIntro(
                            title: "Batch Login Tracker",
                            description: "Monitor each account login step and recover cleanly when one fails.",
                            symbol: "list.number"
                        )

                        Spacer(minLength: DashboardTokens.scaled(10))

                        statusBadge(state: state)
                    }

                    ProgressView(value: Double(state.completedCount), total: Double(max(1, state.totalCount)))
                        .tint(statusColor(state: state))

                    Text(statusLine(state: state))
                        .font(DashboardTokens.Font.metadata().weight(.semibold))
                        .foregroundStyle(statusColor(state: state))
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: metricsColumns, spacing: DashboardTokens.scaled(10)) {
                        trackerMetric(label: "Total", value: "\(state.totalCount)")
                        trackerMetric(label: "Done", value: "\(state.completedCount)")
                        trackerMetric(label: "Success", value: "\(state.successCount)")
                        trackerMetric(label: "Failed", value: "\(state.failedCount)")
                    }
                }
            }

            SettingsPanelCard(padding: DashboardTokens.Spacing.compactCardPadding) {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(10)) {
                    HStack(alignment: .center) {
                        DashboardSectionHeader(title: "Timeline")
                        Spacer(minLength: DashboardTokens.scaled(8))
                        Text("\(state.completedCount)/\(state.totalCount)")
                            .font(DashboardTokens.Font.metadata().weight(.semibold))
                            .foregroundStyle(DashboardTokens.textTertiary)
                            .monospacedDigit()
                    }

                    ScrollView {
                        LazyVStack(spacing: DashboardTokens.scaled(8)) {
                            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                                row(item: item, index: index, isCurrent: state.currentIndex == index)
                            }
                        }
                    }
                    .frame(minHeight: DashboardTokens.scaled(220))
                }
            }

            if state.isFinished {
                SettingsPanelCard(fill: DashboardTokens.cardBackgroundSubtle) {
                    HStack(alignment: .top, spacing: DashboardTokens.scaled(10)) {
                        Image(systemName: state.failedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: DashboardTokens.scaled(11), weight: .semibold))
                            .foregroundStyle(state.failedCount == 0 ? DashboardTokens.statusGreen : DashboardTokens.statusOrange)
                            .padding(.top, DashboardTokens.scaled(2))

                        Text("Finished with \(state.successCount) successful logins, \(state.failedCount) failures, and \(state.cancelledCount) cancelled steps.")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }

            SettingsPanelCard(fill: DashboardTokens.cardBackgroundSubtle) {
                HStack(spacing: DashboardTokens.scaled(8)) {
                    ActionPillButton(
                        title: state.isFinished ? "Run Again" : "Start",
                        symbol: "play.fill",
                        role: .primary,
                        isDisabled: !canStart(state)
                    ) {
                        viewModel.startSequentialNewAccountLogin()
                    }

                    ActionPillButton(
                        title: state.cancellationRequested ? "Stopping" : "Cancel",
                        symbol: "xmark",
                        role: .secondary,
                        isDisabled: !state.isRunning || state.cancellationRequested
                    ) {
                        viewModel.cancelSequentialNewAccountLogin()
                    }

                    ActionPillButton(
                        title: "Retry Failed",
                        symbol: "arrow.clockwise",
                        role: .secondary,
                        isDisabled: !(state.isFinished && state.hasFailures && !state.isRunning)
                    ) {
                        viewModel.retryFailedSequentialNewAccountLogin()
                    }

                    Spacer(minLength: 0)

                    ActionPillButton(
                        title: "Close",
                        symbol: "xmark.circle",
                        role: .secondary
                    ) {
                        dismiss()
                    }
                }
            }
        }
        .padding(DashboardTokens.scaled(16))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(14)) {
            SettingsPanelCard(fill: DashboardTokens.cardBackground) {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(12)) {
                    trackerSectionIntro(
                        title: "No Batch Prepared",
                        description: "Open Accounts settings, choose a count, and start a new batch login.",
                        symbol: "tray"
                    )

                    Text("The tracker appears here only after creating a batch. This keeps the workflow quiet when no background onboarding is running.")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DashboardTokens.scaled(8)) {
                        ActionPillButton(
                            title: "Open Accounts Settings",
                            symbol: "gearshape.fill",
                            role: .primary
                        ) {
                            openAccountsSettingsAndClose()
                        }

                        ActionPillButton(title: "Close", symbol: "xmark.circle", role: .secondary) {
                            dismiss()
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DashboardTokens.scaled(16))
    }

    private func row(item: SequentialLoginItem, index: Int, isCurrent: Bool) -> some View {
        let appearance = rowAppearance(for: item.status)

        return VStack(alignment: .leading, spacing: DashboardTokens.scaled(5)) {
            HStack(spacing: DashboardTokens.scaled(9)) {
                Image(systemName: appearance.symbol)
                    .font(.system(size: DashboardTokens.scaled(11), weight: .semibold))
                    .foregroundStyle(appearance.color)
                    .frame(width: DashboardTokens.scaled(14))

                Text("\(index + 1). \(item.resolvedAccountName ?? item.accountName)")
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DashboardTokens.scaled(10))

                Text(item.status.rawValue.capitalized)
                    .font(.system(size: DashboardTokens.scaled(10), weight: .semibold))
                    .foregroundStyle(appearance.color)
            }

            if let message = item.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                Text(message)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DashboardTokens.scaled(11))
        .padding(.vertical, DashboardTokens.scaled(9))
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(isCurrent ? DashboardTokens.accentBackground.opacity(0.7) : DashboardTokens.cardBackgroundSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(isCurrent ? DashboardTokens.accent.opacity(0.42) : DashboardTokens.cardBorder, lineWidth: 1)
        )
    }

    private func trackerMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(4)) {
            DashboardSectionHeader(title: label)
            Text(value)
                .font(.system(size: DashboardTokens.scaled(16), weight: .semibold))
                .foregroundStyle(DashboardTokens.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DashboardTokens.scaled(10))
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(DashboardTokens.cardBackgroundSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }

    private var metricsColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DashboardTokens.scaled(8)), count: 4)
    }

    private func statusBadge(state: SequentialLoginState) -> some View {
        let color = statusColor(state: state)
        let title: String
        if state.isRunning {
            title = state.cancellationRequested ? "Stopping" : "Running"
        } else if state.isFinished {
            title = state.hasFailures ? "Finished with Issues" : "Completed"
        } else {
            title = "Ready"
        }

        return HStack(spacing: DashboardTokens.scaled(6)) {
            Circle()
                .fill(color)
                .frame(width: DashboardTokens.scaled(7), height: DashboardTokens.scaled(7))
            Text(title)
                .font(.system(size: DashboardTokens.scaled(10), weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, DashboardTokens.scaled(10))
        .padding(.vertical, DashboardTokens.scaled(7))
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.24), lineWidth: 1)
        )
    }

    private func rowAppearance(for status: SequentialLoginItemStatus) -> (color: Color, symbol: String) {
        switch status {
        case .pending:
            return (DashboardTokens.textTertiary, "circle")
        case .inProgress:
            return (DashboardTokens.accent, "arrow.triangle.2.circlepath")
        case .success:
            return (DashboardTokens.statusGreen, "checkmark.circle.fill")
        case .failed:
            return (DashboardTokens.statusRed, "xmark.octagon.fill")
        case .cancelled:
            return (DashboardTokens.statusOrange, "stop.circle.fill")
        }
    }

    private func canStart(_ state: SequentialLoginState) -> Bool {
        !state.isRunning
            && state.totalCount > 0
            && viewModel.accountActionInFlightName == nil
            && viewModel.switchingAccountName == nil
            && viewModel.pendingInteractiveLoginSession?.phase != .waitingForExternalCompletion
    }

    private func statusLine(state: SequentialLoginState) -> String {
        if state.isRunning {
            if state.cancellationRequested {
                return "Stopping after the current step and cleaning unfinished items."
            }
            if let currentIndex = state.currentIndex, currentIndex < state.items.count {
                let current = state.items[currentIndex]
                return "Logging in \(current.accountName) (\(currentIndex + 1) of \(state.totalCount))."
            }
            return "Running batch login."
        }

        if state.isFinished {
            return "Run complete. Review any failed items and retry only what needs attention."
        }

        return "Ready to start this batch."
    }

    private func statusColor(state: SequentialLoginState) -> Color {
        if state.isRunning {
            return state.cancellationRequested ? DashboardTokens.statusOrange : DashboardTokens.accent
        }
        if state.isFinished {
            return state.failedCount == 0 ? DashboardTokens.statusGreen : DashboardTokens.statusOrange
        }
        return DashboardTokens.textSecondary
    }

    private func trackerSectionIntro(title: String, description: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: DashboardTokens.scaled(9)) {
            Image(systemName: symbol)
                .font(DashboardTokens.Font.cardHeading())
                .foregroundStyle(DashboardTokens.accent)
                .frame(width: DashboardTokens.scaled(16))
                .padding(.top, DashboardTokens.scaled(1))

            VStack(alignment: .leading, spacing: DashboardTokens.scaled(4)) {
                Text(title)
                    .font(DashboardTokens.Font.cardHeading())
                    .foregroundStyle(DashboardTokens.textPrimary)

                Text(description)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openAccountsSettingsAndClose() {
        viewModel.selectSettingsSection(.accounts)
        openWindow(id: "settings")
        dismiss()
    }
}
