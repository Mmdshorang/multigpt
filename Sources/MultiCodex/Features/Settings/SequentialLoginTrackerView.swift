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
        VStack(alignment: .leading, spacing: 12) {
            SettingsPanelCard(fill: DashboardTokens.cardBackground) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        trackerSectionIntro(
                            title: "Batch Login Tracker",
                            description: "Monitor each login step and recover cleanly when one fails.",
                            symbol: "list.number"
                        )

                        Spacer(minLength: 8)

                        statusBadge(state: state)
                    }

                    ProgressView(value: Double(state.completedCount), total: Double(max(1, state.totalCount)))
                        .tint(statusColor(state: state))

                    Text(statusLine(state: state))
                        .font(DashboardTokens.Font.metadata().weight(.semibold))
                        .foregroundStyle(statusColor(state: state))
                        .fixedSize(horizontal: false, vertical: true)

                    LazyVGrid(columns: metricsColumns, spacing: 8) {
                        trackerMetric(label: "Total", value: "\(state.totalCount)")
                        trackerMetric(label: "Done", value: "\(state.completedCount)")
                        trackerMetric(label: "Success", value: "\(state.successCount)")
                        trackerMetric(label: "Failed", value: "\(state.failedCount)")
                    }
                }
            }

            SettingsPanelCard(padding: DashboardTokens.Spacing.compactCardPadding) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        DashboardSectionHeader(title: "Timeline")
                        Spacer(minLength: 6)
                        Text("\(state.completedCount)/\(state.totalCount)")
                            .font(DashboardTokens.Font.metadata().weight(.semibold))
                            .foregroundStyle(DashboardTokens.textTertiary)
                            .monospacedDigit()
                    }

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                                row(item: item, index: index, isCurrent: state.currentIndex == index)
                            }
                        }
                    }
                    .frame(minHeight: 200)
                }
            }

            if state.isFinished {
                SettingsPanelCard(fill: DashboardTokens.cardBackgroundSubtle) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: state.failedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(DashboardTokens.Font.metadataBold())
                            .foregroundStyle(state.failedCount == 0 ? DashboardTokens.statusGreen : DashboardTokens.statusOrange)
                            .padding(.top, 1)

                        Text("Finished with \(state.successCount) successful, \(state.failedCount) failed, \(state.cancelledCount) cancelled.")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }

            SettingsPanelCard(fill: DashboardTokens.cardBackgroundSubtle) {
                HStack(spacing: 6) {
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
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPanelCard(fill: DashboardTokens.cardBackground) {
                VStack(alignment: .leading, spacing: 10) {
                    trackerSectionIntro(
                        title: "No Batch Prepared",
                        description: "Open Accounts settings, choose a count, and start a new batch login.",
                        symbol: "tray"
                    )

                    Text("The tracker appears here only after creating a batch. This keeps the workflow quiet when no background onboarding is running.")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
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
        .padding(14)
    }

    // MARK: - Row

    private func row(item: SequentialLoginItem, index: Int, isCurrent: Bool) -> some View {
        let appearance = rowAppearance(for: item.status)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: appearance.symbol)
                    .font(DashboardTokens.Font.caption())
                    .foregroundStyle(appearance.color)
                    .frame(width: 12)

                Text("\(index + 1). \(item.resolvedAccountName ?? item.accountName)")
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(item.status.rawValue.capitalized)
                    .font(DashboardTokens.Font.caption())
                    .foregroundStyle(appearance.color)
            }

            if let message = item.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                Text(message)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(isCurrent ? DashboardTokens.accentBackground.opacity(0.60) : DashboardTokens.cardBackgroundSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(isCurrent ? DashboardTokens.accent.opacity(0.38) : DashboardTokens.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Metric

    private func trackerMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            DashboardSectionHeader(title: label)
            Text(value)
                .font(DashboardTokens.Font.headline())
                .foregroundStyle(DashboardTokens.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
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
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    }

    // MARK: - Status Badge

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

        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(DashboardTokens.Font.caption())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.10))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Helpers

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
                return "Stopping after the current step."
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(DashboardTokens.Font.cardHeading())
                .foregroundStyle(DashboardTokens.accent)
                .frame(width: 14)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
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
