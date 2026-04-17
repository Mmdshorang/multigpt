import SwiftUI

// MARK: - About Page
// App info, version, shortcuts, support

extension SettingsContentView {
    var aboutPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // App Info Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        // App icon placeholder
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

            // Keyboard Shortcuts Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Keyboard Shortcuts",
                        description: "Quick actions from the menu bar"
                    )

                    VStack(spacing: 8) {
                        shortcutRow(keys: "⌘R", action: "Refresh usage")
                        shortcutRow(keys: "⌘,", action: "Open settings")
                    }
                }
            }

            // Support Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Support",
                        description: "Need help or found a bug?"
                    )

                    VStack(spacing: 8) {
                        Link(destination: URL(string: "https://github.com/momoazn/multicodex")!) {
                            HStack {
                                Image(systemName: "arrow.up.forward.square")
                                    .foregroundStyle(DashboardTokens.accent)
                                Text("GitHub Repository")
                                    .foregroundStyle(DashboardTokens.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(DashboardTokens.textTertiary)
                            }
                        }

                        Link(destination: URL(string: "https://github.com/momoazn/multicodex/issues")!) {
                            HStack {
                                Image(systemName: "exclamationmark.bubble")
                                    .foregroundStyle(DashboardTokens.accent)
                                Text("Report an Issue")
                                    .foregroundStyle(DashboardTokens.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(DashboardTokens.textTertiary)
                            }
                        }
                    }
                    .font(DashboardTokens.Font.metadata())
                }
            }
        }
    }

    func shortcutRow(keys: String, action: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(DashboardTokens.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )

            Text(action)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)

            Spacer()
        }
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
