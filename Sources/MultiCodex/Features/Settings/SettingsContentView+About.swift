import SwiftUI

extension SettingsContentView {
    var aboutPage: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(18)) {
            settingsHero(
                title: "About",
                description: "A focused utility for people who actively manage multiple Codex accounts and want the experience to stay clear under pressure.",
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

                    Text("Manage multiple Codex CLI accounts, compare usage at a glance, and keep switching simple when limits or login state change mid-session.")
                        .font(.system(size: DashboardTokens.scaled(12), weight: .regular))
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    settingsInsetPanel(title: "DISCLAIMER") {
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
                        description: "The two commands you are most likely to want when the app is already open.",
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
                        description: "Open the project or report a problem without digging for links.",
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
