import SwiftUI

extension SettingsContentView {
    var aboutPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsHero(
                title: "About",
                description: "Version, shortcuts, and support links.",
                symbol: "app.badge"
            ) {
                settingsBadge(text: "Version \(appVersion)", symbol: "number", color: DashboardTokens.accent)
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DashboardTokens.accentBackground)
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "terminal.fill")
                                    .font(DashboardTokens.Font.headline())
                                    .foregroundStyle(DashboardTokens.accent)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            Text("MultiCodex")
                                .font(DashboardTokens.Font.cardHeading())
                                .foregroundStyle(DashboardTokens.textPrimary)

                            Text("Version \(appVersion)")
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                        }

                        Spacer()
                    }

                    Text("Menu bar utility for managing multiple Codex accounts.")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Rectangle()
                        .fill(DashboardTokens.cardBorder)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 6) {
                        DashboardSectionHeader(title: "Disclaimer")
                        Text("MultiCodex is an independent project and is not affiliated with, endorsed by, or sponsored by OpenAI or the Codex CLI project.")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionIntro(
                        title: "Keyboard Shortcuts",
                        description: "Quick actions.",
                        symbol: "keyboard"
                    )

                    VStack(spacing: 8) {
                        shortcutRow(keys: "\u{2318}R", action: "Refresh usage")
                        shortcutRow(keys: "\u{2318},", action: "Open settings")
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionIntro(
                        title: "Support",
                        description: "Project and issue links.",
                        symbol: "questionmark.circle"
                    )

                    VStack(spacing: 6) {
                        settingsLinkRow(
                            symbol: "arrow.up.forward.square",
                            title: "GitHub Repository",
                            url: "https://github.com/momoazn/multicodex"
                        )

                        settingsLinkRow(
                            symbol: "exclamationmark.bubble",
                            title: "Report an Issue",
                            url: "https://github.com/momoazn/multicodex/issues"
                        )
                    }
                }
            }
        }
    }

    func shortcutRow(keys: String, action: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .font(DashboardTokens.Font.monospaced())
                .foregroundStyle(DashboardTokens.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                        .fill(DashboardTokens.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                        .stroke(DashboardTokens.inputBorder, lineWidth: 1)
                )

            Text(action)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)

            Spacer()
        }
    }

    func settingsLinkRow(symbol: String, title: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.accent)
                    .frame(width: 16)

                Text(title)
                    .font(DashboardTokens.Font.metadata().weight(.medium))
                    .foregroundStyle(DashboardTokens.textPrimary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                    .fill(DashboardTokens.segmentedInactiveBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                    .stroke(DashboardTokens.cardBorder, lineWidth: 1)
            )
        }
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
