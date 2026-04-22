import SwiftUI

struct SequentialLoginTrackerView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DashboardTokens.background
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
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        settingsSectionIntro(
                            title: "Batch Login Tracker",
                            description: "Sequentially create and login new accounts",
                            symbol: "list.number"
                        )
                        Spacer()
                    }

                    HStack(spacing: 8) {
                        trackerMetric(label: "Total", value: "\(state.totalCount)")
                        trackerMetric(label: "Done", value: "\(state.successCount + state.failedCount)")
                        trackerMetric(label: "Success", value: "\(state.successCount)")
                        trackerMetric(label: "Failed", value: "\(state.failedCount)")
                    }
                }
            }

            SettingsPanelCard(padding: 10) {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                            row(item: item, index: index, isCurrent: state.currentIndex == index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 220)
            }

            if state.isFinished {
                SettingsPanelCard {
                    settingsInfoRow(
                        symbol: state.failedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        text: "Finished: \(state.successCount) succeeded, \(state.failedCount) failed.",
                        color: state.failedCount == 0 ? DashboardTokens.statusGreen : DashboardTokens.statusOrange
                    )
                }
            }

            HStack(spacing: 8) {
                ActionPillButton(
                    title: "Start",
                    symbol: "play.fill",
                    role: .primary,
                    isDisabled: !canStart(state)
                ) {
                    viewModel.startSequentialNewAccountLogin()
                }

                ActionPillButton(
                    title: "Cancel",
                    symbol: "xmark",
                    role: .secondary,
                    isDisabled: !state.isRunning
                ) {
                    viewModel.cancelSequentialNewAccountLogin()
                }

                ActionPillButton(
                    title: "Retry Failed Only",
                    symbol: "arrow.clockwise",
                    role: .secondary,
                    isDisabled: !(state.isFinished && state.hasFailures && !state.isRunning)
                ) {
                    viewModel.retryFailedSequentialNewAccountLogin()
                }

                Spacer()

                ActionPillButton(
                    title: "Close",
                    symbol: "xmark.circle",
                    role: .secondary
                ) {
                    dismiss()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPanelCard {
                settingsSectionIntro(
                    title: "No Batch Prepared",
                    description: "Go to Settings > Accounts, pick a count, and click Start Batch Login.",
                    symbol: "tray"
                )
            }

            HStack {
                Spacer()
                ActionPillButton(title: "Close", symbol: "xmark.circle", role: .secondary) {
                    dismiss()
                }
            }
        }
        .padding(14)
    }

    private func row(item: SequentialLoginItem, index: Int, isCurrent: Bool) -> some View {
        let color: Color
        let symbol: String
        switch item.status {
        case .pending:
            color = DashboardTokens.textTertiary
            symbol = "circle"
        case .inProgress:
            color = DashboardTokens.accent
            symbol = "arrow.triangle.2.circlepath"
        case .success:
            color = DashboardTokens.statusGreen
            symbol = "checkmark.circle.fill"
        case .failed:
            color = DashboardTokens.statusRed
            symbol = "xmark.octagon.fill"
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 14)

                Text("\(index + 1). \(item.resolvedAccountName ?? item.accountName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)

                Spacer()

                Text(item.status.rawValue.capitalized)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(color)
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
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill((isCurrent ? DashboardTokens.accent.opacity(0.10) : Color.white.opacity(0.02)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke((isCurrent ? DashboardTokens.accent.opacity(0.35) : Color.white.opacity(0.05)), lineWidth: 1)
        )
    }

    private func trackerMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(DashboardTokens.Font.sectionLabel())
                .foregroundStyle(DashboardTokens.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DashboardTokens.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func canStart(_ state: SequentialLoginState) -> Bool {
        !state.isRunning && state.pendingCount > 0
    }

    private func settingsSectionIntro(title: String, description: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(DashboardTokens.Font.cardHeading())
                .foregroundStyle(DashboardTokens.accent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
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

    private func settingsInfoRow(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(color)
            Text(text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
            Spacer(minLength: 0)
        }
    }
}
