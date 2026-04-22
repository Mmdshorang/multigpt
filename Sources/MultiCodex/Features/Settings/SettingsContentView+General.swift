import SwiftUI

extension SettingsContentView {
    var generalPage: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(18)) {
            settingsHero(
                title: "General",
                description: "Keep the menu bar calm and readable while staying ahead of account availability, refresh health, and automation behavior.",
                symbol: "slider.horizontal.3"
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    if viewModel.isRefreshing {
                        settingsBadge(
                            text: "Refreshing",
                            symbol: "arrow.clockwise",
                            color: DashboardTokens.accent
                        )
                    }
                    settingsBadge(
                        text: viewModel.currentAccount == nil ? "No Active Account" : "\(viewModel.currentAccount?.name ?? "") Active",
                        symbol: viewModel.currentAccount == nil ? "person.crop.circle.badge.questionmark" : "checkmark.circle.fill",
                        color: viewModel.currentAccount == nil ? DashboardTokens.statusOrange : DashboardTokens.statusGreen
                    )
                    settingsBadge(
                        text: viewModel.accountsNeedingLogin.isEmpty ? "All Accounts Healthy" : "\(viewModel.accountsNeedingLogin.count) Need Login",
                        symbol: viewModel.accountsNeedingLogin.isEmpty ? "shield.fill" : "exclamationmark.triangle.fill",
                        color: viewModel.accountsNeedingLogin.isEmpty ? DashboardTokens.statusGreen : DashboardTokens.statusOrange
                    )
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    HStack(alignment: .top, spacing: DashboardTokens.scaled(16)) {
                        settingsSectionIntro(
                            title: "Overview",
                            description: "A quick read on account health and the state of your runtime before you do anything else.",
                            symbol: "chart.bar.fill"
                        )

                        Spacer(minLength: DashboardTokens.scaled(12))

                        HStack(spacing: DashboardTokens.scaled(8)) {
                            ActionPillButton(
                                title: "Refresh",
                                symbol: "arrow.clockwise",
                                role: .secondary,
                                isDisabled: viewModel.isRefreshing
                            ) {
                                viewModel.refresh()
                            }

                            ActionPillButton(
                                title: "Live Refresh",
                                symbol: "bolt.horizontal.fill",
                                role: .primary,
                                isDisabled: viewModel.isRefreshing
                            ) {
                                viewModel.refreshLive()
                            }
                        }
                    }

                    HStack(spacing: DashboardTokens.scaled(12)) {
                        DashboardStatCard(
                            label: "Accounts",
                            value: "\(viewModel.accounts.count)",
                            sublabel: viewModel.accounts.isEmpty ? "Add your first account" : "Configured in MultiCodex"
                        )

                        DashboardStatCard(
                            label: "Active",
                            value: viewModel.currentAccount?.name ?? "None",
                            sublabel: viewModel.currentAccount?.workspaceEmailHint ?? (viewModel.currentAccount == nil ? "No active account" : "Ready")
                        )

                        DashboardStatCard(
                            label: "Need Login",
                            value: "\(viewModel.accountsNeedingLogin.count)",
                            sublabel: viewModel.accountsNeedingLogin.isEmpty ? "No action needed" : "Accounts need attention"
                        )
                    }

                    if let warning = viewModel.refreshWarningMessage {
                        SubtleWarningRow(text: warning)
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    settingsSectionIntro(
                        title: "Menu Appearance",
                        description: "Tune information density without losing the calm, glanceable quality a menu bar utility needs.",
                        symbol: "paintbrush.fill"
                    )

                    VStack(spacing: DashboardTokens.scaled(16)) {
                        settingsFormRow("Menu density", detail: "Control how many accounts the menu shows before collapsing overflow.", icon: "rectangle.compress.vertical") {
                            SettingsSegmentedPicker(
                                options: MenuDensity.allCases,
                                titleForOption: { $0.title },
                                selection: menuDensityBinding
                            )
                            .frame(maxWidth: DashboardTokens.scaled(320))
                        }

                        settingsFormRow("Reset time display", detail: "Choose the format that is easiest to scan during quick status checks.", icon: "clock") {
                            SettingsSegmentedPicker(
                                options: ResetDisplayMode.allCases,
                                titleForOption: { $0.title },
                                selection: resetDisplayModeBinding
                            )
                            .frame(maxWidth: DashboardTokens.scaled(320))
                        }

                        settingsFormRow("Usage bar style", detail: viewModel.usageBarStyle.descriptionText, icon: "chart.bar") {
                            SettingsSegmentedPicker(
                                options: UsageBarStyle.allCases,
                                titleForOption: { $0.title },
                                selection: usageBarStyleBinding
                            )
                            .frame(maxWidth: DashboardTokens.scaled(320))
                        }
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    settingsSectionIntro(
                        title: "Auto-Switching",
                        description: "Let MultiCodex recover gracefully when an account is exhausted or needs to be re-authenticated.",
                        symbol: "arrow.triangle.swap"
                    )

                    VStack(spacing: DashboardTokens.scaled(16)) {
                        settingsFormRow("Strategy", detail: viewModel.accountSwitchingStrategy.descriptionText, icon: "arrow.2.circlepath") {
                            SettingsSegmentedPicker(
                                options: AccountSwitchingStrategy.allCases,
                                titleForOption: { $0.title },
                                selection: accountSwitchingStrategyBinding
                            )
                            .frame(maxWidth: DashboardTokens.scaled(360))
                        }

                        settingsInsetPanel(title: "NOTIFICATIONS", description: "Keep notifications available for automatic changes, then send a quick test to confirm the experience feels right.") {
                            HStack(spacing: DashboardTokens.scaled(12)) {
                                SettingsToggle(label: "Show notifications", isOn: autoSwitchNotificationsBinding)

                                Spacer(minLength: DashboardTokens.scaled(12))

                                ActionPillButton(
                                    title: "Send Test",
                                    symbol: "bell.badge",
                                    role: .secondary,
                                    isDisabled: !viewModel.autoSwitchNotificationsEnabled
                                ) {
                                    viewModel.sendTestAutoSwitchNotification()
                                }
                            }
                        }

                        if let message = viewModel.accountActionMessage {
                            feedbackRow(message, color: DashboardTokens.statusGreen)
                        }

                        if let error = viewModel.accountActionError {
                            feedbackRow(error, color: DashboardTokens.statusRed)
                        }
                    }
                }
            }
        }
    }
}
