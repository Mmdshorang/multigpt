import SwiftUI

extension SettingsContentView {
    var aboutPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DashboardTokens.accent.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(DashboardTokens.accent)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("MultiCodex")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(DashboardTokens.textPrimary)

                            Text("Version \(appVersion)")
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                        }

                        Spacer()
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    Text("Manage multiple Codex CLI accounts with ease. Switch between accounts, track usage, and stay within rate limits.")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Keyboard Shortcuts",
                        description: "Quick actions from the menu bar",
                        symbol: "keyboard"
                    )

                    VStack(spacing: 6) {
                        shortcutRow(keys: "⌘R", action: "Refresh usage")
                        shortcutRow(keys: "⌘,", action: "Open settings")
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Support",
                        description: "Need help or found a bug?",
                        symbol: "questionmark.circle"
                    )

                    VStack(spacing: 4) {
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
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTokens.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DashboardTokens.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
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
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textPrimary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DashboardTokens.segmentedInactiveBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DashboardTokens.cardBorder, lineWidth: 1)
            )
        }
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
