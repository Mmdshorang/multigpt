import SwiftUI

extension SettingsContentView {
    var settingsContentMaxWidth: CGFloat { 640 }

    var settingsBackground: some View {
        DashboardTokens.background
            .ignoresSafeArea()
    }

    func settingsSectionIntro(
        title: String,
        description: String
    ) -> some View {
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

    func settingsInsetPanel<Content: View>(
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                DashboardSectionHeader(title: title)
            }

            if let description {
                Text(description)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DashboardTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    func settingsFormRow<Control: View>(
        _ label: String,
        detail: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)

                if let detail {
                    Text(detail)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func settingsInfoRow(symbol: String, text: String, color: Color = DashboardTokens.textSecondary) -> some View {
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

    // MARK: - Feedback Row

    func feedbackRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textPrimary)

            Spacer()

            Button("Dismiss") {
                viewModel.clearAccountActionFeedback()
            }
            .buttonStyle(.plain)
            .font(DashboardTokens.Font.metadata().weight(.semibold))
            .foregroundStyle(DashboardTokens.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            color.opacity(0.10),
            in: RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
        )
    }
}
