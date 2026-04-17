import SwiftUI

extension SettingsContentView {
    var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        settingsSectionIntro(
                            title: "Status",
                            description: "Current system overview",
                            symbol: "chart.bar.fill"
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

                    HStack(spacing: 8) {
                        DashboardStatCard(
                            label: "Accounts",
                            value: "\(viewModel.accounts.count)"
                        )

                        DashboardStatCard(
                            label: "Current",
                            value: viewModel.currentAccount?.name ?? "None",
                            sublabel: viewModel.currentAccount != nil ? "Active" : nil
                        )

                        DashboardStatCard(
                            label: "Need Login",
                            value: "\(viewModel.accountsNeedingLogin.count)",
                            sublabel: viewModel.accountsNeedingLogin.isEmpty ? "All good" : "Action needed"
                        )
                    }

                    if let warning = viewModel.refreshWarningMessage {
                        SubtleWarningRow(text: warning)
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Appearance",
                        description: "Customize menu bar display",
                        symbol: "paintbrush.fill"
                    )

                    VStack(spacing: 14) {
                        settingsFormRow("Menu density", icon: "rectangle.compress.vertical") {
                            SettingsSegmentedPicker(
                                options: MenuDensity.allCases,
                                titleForOption: { $0.title },
                                selection: menuDensityBinding
                            )
                            .frame(maxWidth: 260)
                        }

                        settingsFormRow("Reset time display", icon: "clock") {
                            SettingsSegmentedPicker(
                                options: ResetDisplayMode.allCases,
                                titleForOption: { $0.title },
                                selection: resetDisplayModeBinding
                            )
                            .frame(maxWidth: 260)
                        }

                        settingsFormRow("Usage bar style", icon: "chart.bar") {
                            SettingsSegmentedPicker(
                                options: UsageBarStyle.allCases,
                                titleForOption: { $0.title },
                                selection: usageBarStyleBinding
                            )
                            .frame(maxWidth: 260)
                        }
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Auto-Switching",
                        description: "Automatically switch between accounts",
                        symbol: "arrow.triangle.swap"
                    )

                    VStack(spacing: 14) {
                        settingsFormRow("Strategy", detail: viewModel.accountSwitchingStrategy.descriptionText, icon: "arrow.2.circlepath") {
                            SettingsSegmentedPicker(
                                options: AccountSwitchingStrategy.allCases,
                                titleForOption: { $0.title },
                                selection: accountSwitchingStrategyBinding
                            )
                            .frame(maxWidth: 300)
                        }

                        HStack(spacing: 10) {
                            SettingsToggle(label: "Show notifications", isOn: autoSwitchNotificationsBinding)

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
}
