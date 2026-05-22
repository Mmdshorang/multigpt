import SwiftUI

extension SettingsContentView {
    var settingsContentMaxWidth: CGFloat { 720 }

    var settingsBackground: some View {
        DashboardTokens.backgroundGradient
            .ignoresSafeArea()
    }

    // MARK: - Hero

    func settingsHero(
        title: String,
        description: String,
        symbol: String
    ) -> some View {
        settingsHero(title: title, description: description, symbol: symbol) {
            EmptyView()
        }
    }

    func settingsHero<Accessory: View>(
        title: String,
        description: String,
        symbol: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        SettingsPanelCard(padding: DashboardTokens.Spacing.heroPadding, fill: DashboardTokens.cardBackground) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DashboardTokens.accentBackground)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: symbol)
                            .font(DashboardTokens.Font.detailTitle())
                            .foregroundStyle(DashboardTokens.accent)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(DashboardTokens.Font.detailTitle())
                        .foregroundStyle(DashboardTokens.textPrimary)

                    Text(description)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                accessory()
            }
        }
    }

    // MARK: - Section Intro

    func settingsSectionIntro(
        title: String,
        description: String,
        symbol: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(DashboardTokens.Font.cardHeading())
                    .foregroundStyle(DashboardTokens.accent)
                    .frame(width: 16)
                    .padding(.top, 1)
            }

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

    // MARK: - Form Row

    func settingsFormRow<Control: View>(
        _ label: String,
        detail: String? = nil,
        icon: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(DashboardTokens.Font.formLabel())
                        .foregroundStyle(DashboardTokens.textTertiary)
                        .frame(width: 16)
                        .padding(.top, 1)
                }

                VStack(alignment: .leading, spacing: 3) {
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
            }

            Spacer(minLength: 14)

            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inset Panel

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
        .padding(DashboardTokens.Spacing.compactCardPadding)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                    .fill(DashboardTokens.cardBackgroundSubtle)
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                    .fill(DashboardTokens.glassHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Info Row

    func settingsInfoRow(symbol: String, text: String, color: Color = DashboardTokens.textSecondary) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 14)
                .padding(.top, 1)
            Text(text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Badge

    func settingsBadge(text: String, symbol: String? = nil, color: Color) -> some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(DashboardTokens.Font.microLabel())
            }

            Text(text)
                .font(DashboardTokens.Font.caption())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.10))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.20), lineWidth: 0.5)
        )
    }

    // MARK: - Feedback Row

    func feedbackRow(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, 3)

            Text(text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 10)

            if viewModel.canCancelLogin {
                Button("Cancel Login") {
                    viewModel.cancelLogin()
                }
                .buttonStyle(.plain)
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(DashboardTokens.statusOrange)
            }

            Button("Dismiss") {
                viewModel.clearAccountActionFeedback()
            }
            .buttonStyle(.plain)
            .font(DashboardTokens.Font.metadata().weight(.semibold))
            .foregroundStyle(DashboardTokens.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            color.opacity(0.08),
            in: RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(color.opacity(0.16), lineWidth: 0.5)
        )
    }
}
