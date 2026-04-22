import SwiftUI

extension SettingsContentView {
    var aboutPage: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(18)) {
            settingsHero(
                title: "About",
                description: "Version, shortcuts, and support links.",
                symbol: "app.badge"
            ) {
                settingsBadge(text: "Version \(appVersion)", symbol: "number", color: DashboardTokens.accent)
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    HStack(spacing: DashboardTokens.scaled(14)) {
                        RoundedRectangle(cornerRadius: DashboardTokens.scaled(16), style: .continuous)
                            .fill(DashboardTokens.accentBackground)
                            .frame(width: DashboardTokens.scaled(54), height: DashboardTokens.scaled(54))
                            .overlay(
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: DashboardTokens.scaled(23), weight: .semibold))
                                    .foregroundStyle(DashboardTokens.accent)
                            )

                        VStack(alignment: .leading, spacing: DashboardTokens.scaled(5)) {
                            Text("MultiCodex")
                                .font(.system(size: DashboardTokens.scaled(19), weight: .semibold))
                                .foregroundStyle(DashboardTokens.textPrimary)

                            Text("Version \(appVersion)")
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                        }

                        Spacer()
                    }

                    Text("Menu bar utility for managing multiple Codex accounts.")
                        .font(.system(size: DashboardTokens.scaled(12), weight: .regular))
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Rectangle()
                        .fill(DashboardTokens.cardBorder)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: DashboardTokens.scaled(8)) {
                        DashboardSectionHeader(title: "Disclaimer")
                        Text("MultiCodex is an independent project and is not affiliated with, endorsed by, or sponsored by OpenAI or the Codex CLI project.")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    settingsSectionIntro(
                        title: "Keyboard Shortcuts",
                        description: "Quick actions.",
                        symbol: "keyboard"
                    )

                    VStack(spacing: DashboardTokens.scaled(10)) {
                        shortcutRow(keys: "⌘R", action: "Refresh usage")
                        shortcutRow(keys: "⌘,", action: "Open settings")
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    settingsSectionIntro(
                        title: "Support",
                        description: "Project and issue links.",
                        symbol: "questionmark.circle"
                    )

                    VStack(spacing: DashboardTokens.scaled(8)) {
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
        HStack(spacing: DashboardTokens.scaled(12)) {
            Text(keys)
                .font(.system(size: DashboardTokens.scaled(12), weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTokens.textPrimary)
                .padding(.horizontal, DashboardTokens.scaled(10))
                .padding(.vertical, DashboardTokens.scaled(7))
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
            HStack(spacing: DashboardTokens.scaled(12)) {
                Image(systemName: symbol)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.accent)
                    .frame(width: DashboardTokens.scaled(18))

                Text(title)
                    .font(DashboardTokens.Font.metadata().weight(.medium))
                    .foregroundStyle(DashboardTokens.textPrimary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textTertiary)
            }
            .padding(.horizontal, DashboardTokens.scaled(12))
            .padding(.vertical, DashboardTokens.scaled(10))
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
