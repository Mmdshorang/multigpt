import SwiftUI

extension SettingsContentView {
    var systemPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsHero(
                title: "System",
                description: "Runtime path, diagnostics, and refresh settings.",
                symbol: "terminal.fill"
            ) {
                settingsBadge(
                    text: viewModel.isCodexRuntimeAvailable ? "Runtime Ready" : "Needs Attention",
                    symbol: runtimeStatus.symbol,
                    color: runtimeStatus.color
                )
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionIntro(
                        title: "Runtime",
                        description: "Configure Codex executable resolution.",
                        symbol: "terminal"
                    )

                    HStack(alignment: .top, spacing: 10) {
                        settingsBadge(text: runtimeStatus.text, symbol: runtimeStatus.symbol, color: runtimeStatus.color)
                        Spacer(minLength: 0)
                    }

                    Rectangle()
                        .fill(DashboardTokens.cardBorder)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 6) {
                        DashboardSectionHeader(title: "Executable")
                        Text("Set a custom `codex` path when auto-detection fails.")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)

                        HStack(spacing: 8) {
                            SettingsTextField(
                                placeholder: "/opt/homebrew/bin/codex",
                                text: $codexPathDraft
                            )

                            ActionPillButton(title: "Choose", symbol: "folder") {
                                viewModel.chooseCustomCodexPath()
                            }
                        }

                        HStack(spacing: 6) {
                            ActionPillButton(title: "Save Path", symbol: "checkmark", role: .primary) {
                                viewModel.updateCustomCodexPath(codexPathDraft)
                            }
                            .disabled(normalized(codexPathDraft) == viewModel.customCodexPath)

                            ActionPillButton(title: "Use Automatic Detection", symbol: "sparkles") {
                                codexPathDraft = ""
                                viewModel.clearCustomCodexPath()
                            }
                            .disabled(viewModel.customCodexPath.isEmpty)
                        }
                    }

                    if let probe = viewModel.runtimeProbeSummary, !probe.isEmpty {
                        settingsInfoRow(symbol: "info.circle", text: probe, color: DashboardTokens.textTertiary)
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionIntro(
                        title: "Diagnostics",
                        description: "Open config and inspect runtime resolution.",
                        symbol: "stethoscope"
                    )

                    HStack(spacing: 6) {
                        ActionPillButton(title: "Open Config Folder", symbol: "folder.fill") {
                            viewModel.openMulticodexConfigDirectory()
                        }

                        ActionPillButton(title: "Run Live Refresh", symbol: "bolt.horizontal.fill", role: .primary) {
                            viewModel.refreshLive()
                        }
                    }

                    if let hint = viewModel.cliResolutionHint {
                        Rectangle()
                            .fill(DashboardTokens.cardBorder)
                            .frame(height: 1)

                        VStack(alignment: .leading, spacing: 6) {
                            DashboardSectionHeader(title: "Resolution Notes")
                            Text(hint)
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        settingsInfoRow(
                            symbol: "arrow.clockwise",
                            text: "Run Live Refresh to populate resolution notes.",
                            color: DashboardTokens.textTertiary
                        )
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSectionIntro(
                        title: "Refresh Cache",
                        description: "Background refresh interval.",
                        symbol: "timer"
                    )

                    settingsFormRow("Refresh interval", detail: "How often background usage data is refreshed.", icon: "arrow.triangle.2.circlepath") {
                        HStack(spacing: 10) {
                            Text("\(viewModel.limitsCacheTTLMinutes) min")
                                .font(DashboardTokens.Font.metadata().weight(.semibold))
                                .foregroundStyle(DashboardTokens.textPrimary)
                                .monospacedDigit()

                            Stepper("", value: limitsCacheTTLMinutesBinding, in: 1...120)
                                .labelsHidden()
                        }
                    }

                    settingsInfoRow(
                        symbol: "lightbulb",
                        text: "Lower values refresh more often and increase CLI activity.",
                        color: DashboardTokens.textTertiary
                    )
                }
            }
        }
    }
}
