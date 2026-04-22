import SwiftUI

extension SettingsContentView {
    var settingsContentMaxWidth: CGFloat { DashboardTokens.scaled(760) }

    var settingsBackground: some View {
        DashboardTokens.backgroundGradient
            .ignoresSafeArea()
    }

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
            HStack(alignment: .top, spacing: DashboardTokens.scaled(16)) {
                RoundedRectangle(cornerRadius: DashboardTokens.scaled(18), style: .continuous)
                    .fill(DashboardTokens.accentBackground)
                    .frame(width: DashboardTokens.scaled(48), height: DashboardTokens.scaled(48))
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: DashboardTokens.scaled(20), weight: .semibold))
                            .foregroundStyle(DashboardTokens.accent)
                    )

                VStack(alignment: .leading, spacing: DashboardTokens.scaled(8)) {
                    Text(title)
                        .font(DashboardTokens.Font.detailTitle())
                        .foregroundStyle(DashboardTokens.textPrimary)

                    Text(description)
                        .font(.system(size: DashboardTokens.scaled(12), weight: .regular))
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DashboardTokens.scaled(12))

                accessory()
            }
        }
    }

    func settingsSectionIntro(
        title: String,
        description: String,
        symbol: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: DashboardTokens.scaled(10)) {
            if let symbol {
                Image(systemName: symbol)
                    .font(DashboardTokens.Font.cardHeading())
                    .foregroundStyle(DashboardTokens.accent)
                    .frame(width: DashboardTokens.scaled(18))
                    .padding(.top, DashboardTokens.scaled(1))
            }

            VStack(alignment: .leading, spacing: DashboardTokens.scaled(5)) {
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

    func settingsFormRow<Control: View>(
        _ label: String,
        detail: String? = nil,
        icon: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: DashboardTokens.scaled(16)) {
            HStack(alignment: .top, spacing: DashboardTokens.scaled(10)) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: DashboardTokens.scaled(11), weight: .medium))
                        .foregroundStyle(DashboardTokens.textTertiary)
                        .frame(width: DashboardTokens.scaled(18))
                        .padding(.top, DashboardTokens.scaled(1))
                }

                VStack(alignment: .leading, spacing: DashboardTokens.scaled(4)) {
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

            Spacer(minLength: DashboardTokens.scaled(16))

            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func settingsInsetPanel<Content: View>(
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(10)) {
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
                .fill(DashboardTokens.cardBackgroundSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }

    func settingsInfoRow(symbol: String, text: String, color: Color = DashboardTokens.textSecondary) -> some View {
        HStack(alignment: .top, spacing: DashboardTokens.scaled(8)) {
            Image(systemName: symbol)
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(color)
                .frame(width: DashboardTokens.scaled(16))
                .padding(.top, DashboardTokens.scaled(1))
            Text(text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    func settingsBadge(text: String, symbol: String? = nil, color: Color) -> some View {
        HStack(spacing: DashboardTokens.scaled(6)) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: DashboardTokens.scaled(9), weight: .semibold))
            }

            Text(text)
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

    func feedbackRow(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: DashboardTokens.scaled(10)) {
            Circle()
                .fill(color)
                .frame(width: DashboardTokens.scaled(8), height: DashboardTokens.scaled(8))
                .padding(.top, DashboardTokens.scaled(4))

            Text(text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DashboardTokens.scaled(12))

            Button("Dismiss") {
                viewModel.clearAccountActionFeedback()
            }
            .buttonStyle(.plain)
            .font(DashboardTokens.Font.metadata().weight(.semibold))
            .foregroundStyle(DashboardTokens.textSecondary)
        }
        .padding(.horizontal, DashboardTokens.scaled(12))
        .padding(.vertical, DashboardTokens.scaled(10))
        .background(
            color.opacity(0.10),
            in: RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}
