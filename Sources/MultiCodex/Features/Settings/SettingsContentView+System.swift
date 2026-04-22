import SwiftUI

extension SettingsContentView {
    var systemPage: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(18)) {
            settingsHero(
                title: "System",
                description: "Keep the Codex runtime trustworthy, make diagnostics obvious, and avoid mysterious failures caused by path or refresh issues.",
                symbol: "terminal.fill"
            ) {
                settingsBadge(
                    text: viewModel.isCodexRuntimeAvailable ? "Runtime Ready" : "Runtime Needs Attention",
                    symbol: runtimeStatus.symbol,
                    color: runtimeStatus.color
                )
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    settingsSectionIntro(
                        title: "Runtime",
                        description: "Use automatic detection when possible, and only pin a custom path when you need deterministic behavior.",
                        symbol: "terminal"
                    )

                    HStack(alignment: .top, spacing: DashboardTokens.scaled(12)) {
                        settingsBadge(text: runtimeStatus.text, symbol: runtimeStatus.symbol, color: runtimeStatus.color)
                        Spacer(minLength: 0)
                    }

                    settingsInsetPanel(title: "EXECUTABLE", description: "Point MultiCodex to the exact `codex` binary if automatic resolution is not finding the right one.") {
                        VStack(alignment: .leading, spacing: DashboardTokens.scaled(10)) {
                            HStack(spacing: DashboardTokens.scaled(10)) {
                                SettingsTextField(
                                    placeholder: "/opt/homebrew/bin/codex",
                                    text: $codexPathDraft
                                )

                                ActionPillButton(title: "Choose", symbol: "folder") {
                                    viewModel.chooseCustomCodexPath()
                                }
                            }

                            HStack(spacing: DashboardTokens.scaled(8)) {
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
                    }

                    if let probe = viewModel.runtimeProbeSummary, !probe.isEmpty {
                        settingsInfoRow(symbol: "info.circle", text: probe, color: DashboardTokens.textTertiary)
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    settingsSectionIntro(
                        title: "Diagnostics",
                        description: "Surface the operational details you need without forcing you into the terminal for every small question.",
                        symbol: "stethoscope"
                    )

                    HStack(spacing: DashboardTokens.scaled(8)) {
                        ActionPillButton(title: "Open Config Folder", symbol: "folder.fill") {
                            viewModel.openMulticodexConfigDirectory()
                        }

                        ActionPillButton(title: "Run Live Refresh", symbol: "bolt.horizontal.fill", role: .primary) {
                            viewModel.refreshLive()
                        }
                    }

                    if let hint = viewModel.cliResolutionHint {
                        settingsInsetPanel(title: "RESOLUTION NOTES") {
                            Text(hint)
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        settingsInfoRow(
                            symbol: "arrow.clockwise",
                            text: "Run a live refresh to capture fresh runtime resolution details.",
                            color: DashboardTokens.textTertiary
                        )
                    }
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    settingsSectionIntro(
                        title: "Refresh Cache",
                        description: "A shorter interval feels more alive, but a slightly longer interval is often calmer and easier on the CLI.",
                        symbol: "timer"
                    )

                    settingsFormRow("Refresh interval", detail: "Choose how often background usage data is refreshed.", icon: "arrow.triangle.2.circlepath") {
                        HStack(spacing: DashboardTokens.scaled(12)) {
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
                        text: "Lower values update more frequently but may cost responsiveness and make the app feel busier than it needs to.",
                        color: DashboardTokens.textTertiary
                    )
                }
            }
        }
    }
}
