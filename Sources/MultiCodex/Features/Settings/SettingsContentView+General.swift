import SwiftUI

// MARK: - General Page
// Merges Dashboard overview + Display settings

extension SettingsContentView {
    var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status Overview Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        settingsSectionIntro(
                            title: "Status",
                            description: "Current system overview"
                        )

                        Spacer()

                        HStack(spacing: 8) {
                            ActionPillButton(
                                title: "Refresh",
                                symbol: "arrow.clockwise",
                                role: .secondary,
                                layout: .iconOnly
                            ) {
                                viewModel.refresh()
                            }

                            ActionPillButton(
                                title: "Live",
                                symbol: "bolt.horizontal.fill",
                                role: .primary
                            ) {
                                viewModel.refreshLive()
                            }
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    HStack(spacing: 16) {
                        statusItem(
                            label: "Accounts",
                            value: "\(viewModel.accounts.count)",
                            symbol: "person.2.fill"
                        )

                        statusItem(
                            label: "Current",
                            value: viewModel.currentAccount?.name ?? "None",
                            symbol: "checkmark.circle.fill",
                            valueColor: viewModel.currentAccount != nil ? DashboardTokens.statusGreen : DashboardTokens.textSecondary
                        )

                        statusItem(
                            label: "Need Login",
                            value: "\(viewModel.accountsNeedingLogin.count)",
                            symbol: "exclamationmark.triangle.fill",
                            valueColor: viewModel.accountsNeedingLogin.isEmpty ? DashboardTokens.textSecondary : DashboardTokens.statusRed
                        )
                    }

                    if let warning = viewModel.refreshWarningMessage {
                        SubtleWarningRow(text: warning)
                    }
                }
            }

            // Display Settings Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Appearance",
                        description: "Customize menu bar display"
                    )

                    VStack(spacing: 12) {
                        settingsFormRow("Menu density") {
                            Picker("Menu density", selection: menuDensityBinding) {
                                ForEach(MenuDensity.allCases) { density in
                                    Text(density.title).tag(density)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        settingsFormRow("Reset time display") {
                            Picker("Reset time style", selection: resetDisplayModeBinding) {
                                ForEach(ResetDisplayMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        settingsFormRow("Usage bar style") {
                            Picker("Usage bars", selection: usageBarStyleBinding) {
                                ForEach(UsageBarStyle.allCases) { style in
                                    Text(style.title).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                }
            }

            // Account Switching Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Auto-Switching",
                        description: "Automatically switch between accounts"
                    )

                    VStack(spacing: 12) {
                        settingsFormRow("Strategy") {
                            Picker("Switching strategy", selection: accountSwitchingStrategyBinding) {
                                ForEach(AccountSwitchingStrategy.allCases) { strategy in
                                    Text(strategy.title).tag(strategy)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        HStack(spacing: 10) {
                            Toggle("Show notifications", isOn: autoSwitchNotificationsBinding)
                                .toggleStyle(.switch)

                            Spacer()

                            ActionPillButton(
                                title: "Test",
                                symbol: "bell.badge",
                                isDisabled: !viewModel.autoSwitchNotificationsEnabled
                            ) {
                                viewModel.sendTestAutoSwitchNotification()
                            }
                        }
                    }
                }
            }
        }
    }

    func statusItem(label: String, value: String, symbol: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DashboardTokens.textTertiary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textTertiary)

                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(valueColor ?? DashboardTokens.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
