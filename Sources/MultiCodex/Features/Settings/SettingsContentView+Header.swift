import SwiftUI

extension SettingsContentView {
    // MARK: - Header Card (used across pages)

    var headerCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    settingsInfoRow(symbol: "person.2.fill", text: "\(viewModel.accounts.count) accounts")
                    runtimeStatusInfoRow

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        ActionPillButton(
                            title: "Refresh",
                            symbol: "arrow.clockwise",
                            role: .secondary,
                            layout: .iconOnly
                        ) {
                            viewModel.refresh()
                        }

                        ActionPillButton(title: "Refresh Live", symbol: "bolt.horizontal.fill", role: .primary) {
                            viewModel.refreshLive()
                        }
                    }
                }

                if let warning = viewModel.refreshWarningMessage {
                    SubtleWarningRow(text: warning)
                }
            }
        }
    }

    // MARK: - Shared Diagnostics Components

    /// Standard runtime status info row used across multiple settings pages
    var runtimeStatusInfoRow: some View {
        settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)
    }

    /// Standard CLI resolution hint display used in troubleshooting/advanced pages
    var cliResolutionHintRow: some View {
        Group {
            if let hint = viewModel.cliResolutionHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Run a refresh to capture command resolution details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Standard refresh warning banner
    var refreshWarningBanner: some View {
        Group {
            if let warning = viewModel.refreshWarningMessage {
                SubtleWarningRow(text: warning)
            }
        }
    }

    // MARK: - Feedback Row

    func feedbackRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)

            Spacer()

            Button("Dismiss") {
                viewModel.clearAccountActionFeedback()
            }
            .buttonStyle(.plain)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
