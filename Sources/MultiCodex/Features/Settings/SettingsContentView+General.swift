import SwiftUI

extension SettingsContentView {
    var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsHero(
                title: "General",
                description: "Behavior and menu display settings.",
                symbol: "slider.horizontal.3"
            ) {
                VStack(alignment: .trailing, spacing: 6) {
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
                        text: viewModel.accountsNeedingLogin.isEmpty ? "All Healthy" : "\(viewModel.accountsNeedingLogin.count) Need Login",
                        symbol: viewModel.accountsNeedingLogin.isEmpty ? "shield.fill" : "exclamationmark.triangle.fill",
                        color: viewModel.accountsNeedingLogin.isEmpty ? DashboardTokens.statusGreen : DashboardTokens.statusOrange
                    )
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        settingsSectionIntro(
                            title: "Overview",
                            description: "Account and runtime status.",
                            symbol: "chart.bar.fill"
                        )

                        Spacer(minLength: 10)

                        HStack(spacing: 6) {
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

                    HStack(spacing: 10) {
                        DashboardStatCard(
                            label: "Accounts",
                            value: "\(viewModel.accounts.count)",
                            sublabel: viewModel.accounts.isEmpty ? "No accounts" : "Configured"
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
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionIntro(
                        title: "Menu Appearance",
                        description: "Control density and display format.",
                        symbol: "paintbrush.fill"
                    )

                    VStack(spacing: 14) {
                        settingsFormRow("Menu density", detail: "How many accounts the menu shows before collapsing overflow.", icon: "rectangle.compress.vertical") {
                            SettingsSegmentedPicker(
                                options: MenuDensity.allCases,
                                titleForOption: { $0.title },
                                selection: menuDensityBinding
                            )
                            .frame(maxWidth: 300)
                        }

                        settingsFormRow("Reset time display", detail: "Format that is easiest to scan during quick status checks.", icon: "clock") {
                            SettingsSegmentedPicker(
                                options: ResetDisplayMode.allCases,
                                titleForOption: { $0.title },
                                selection: resetDisplayModeBinding
                            )
                            .frame(maxWidth: 300)
                        }

                        settingsFormRow("Usage bar style", detail: viewModel.usageBarStyle.descriptionText, icon: "chart.bar") {
                            SettingsSegmentedPicker(
                                options: UsageBarStyle.allCases,
                                titleForOption: { $0.title },
                                selection: usageBarStyleBinding
                            )
                            .frame(maxWidth: 300)
                        }
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionIntro(
                        title: "Auto-Switching",
                        description: "Automatic account switching behavior.",
                        symbol: "arrow.triangle.swap"
                    )

                    VStack(spacing: 14) {
                        settingsFormRow("Strategy", detail: viewModel.accountSwitchingStrategy.descriptionText, icon: "arrow.2.circlepath") {
                            SettingsSegmentedPicker(
                                options: AccountSwitchingStrategy.allCases,
                                titleForOption: { $0.title },
                                selection: accountSwitchingStrategyBinding
                            )
                            .frame(maxWidth: 340)
                        }

                        Rectangle()
                            .fill(DashboardTokens.cardBorder)
                            .frame(height: 1)

                        VStack(alignment: .leading, spacing: 6) {
                            DashboardSectionHeader(title: "Notifications")
                            Text("Enable notifications and send a test alert.")
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)

                            HStack(spacing: 10) {
                                SettingsToggle(label: "Show notifications", isOn: autoSwitchNotificationsBinding)

                                Spacer(minLength: 10)

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
