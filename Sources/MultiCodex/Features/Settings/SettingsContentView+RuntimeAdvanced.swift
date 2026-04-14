import SwiftUI

extension SettingsContentView {
    // MARK: - Runtime Page

    var runtimePage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro(
                    title: "Runtime",
                    description: "Choose a custom CLI path or use auto-detect."
                )

                settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)

                TextField("/opt/homebrew/bin/codex", text: $codexPathDraft)
                    .textFieldStyle(.roundedBorder)

                if let probe = viewModel.runtimeProbeSummary {
                    Text(probe)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Leave this empty to auto-detect `codex` from known paths or from your shell PATH.")
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)

                HStack(spacing: 8) {
                    ActionPillButton(title: "Save", symbol: "checkmark", role: .primary) {
                        viewModel.updateCustomCodexPath(codexPathDraft)
                    }
                    .disabled(normalized(codexPathDraft) == viewModel.customCodexPath)

                    ActionPillButton(title: "Choose", symbol: "folder") {
                        viewModel.chooseCustomCodexPath()
                    }

                    ActionPillButton(title: "Use Auto", symbol: "sparkles") {
                        codexPathDraft = ""
                        viewModel.clearCustomCodexPath()
                    }
                    .disabled(viewModel.customCodexPath.isEmpty)
                }
            }
        }
    }

    // MARK: - Display Page

    var displayPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro(
                    title: "Display",
                    description: "Choose how the menu feels and how usage information is shown."
                )

                settingsInsetPanel(
                    title: "Menu Layout",
                    description: "Controls how dense the menu feels and how reset times are presented."
                ) {
                    settingsFormRow("Density", detail: "Compact shows more at once. Comfortable adds breathing room.") {
                        Picker("Menu density", selection: menuDensityBinding) {
                            ForEach(MenuDensity.allCases) { density in
                                Text(density.title).tag(density)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    settingsFormRow("Reset time style", detail: viewModel.resetDisplayMode.descriptionText) {
                        Picker("Reset time style", selection: resetDisplayModeBinding) {
                            ForEach(ResetDisplayMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }

                settingsInsetPanel(
                    title: "Usage Indicators",
                    description: "Pick whether the bars emphasize remaining budget or usage consumed."
                ) {
                    settingsFormRow("Usage bars", detail: viewModel.usageBarStyle.descriptionText) {
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
    }

    // MARK: - Troubleshooting Page

    var troubleshootingPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro(
                    title: "Troubleshooting",
                    description: "Diagnostics and refresh controls."
                )

                cliResolutionHintRow

                settingsFormRow("Cache TTL", detail: "Controls how often usage limits refresh automatically.") {
                    Stepper(value: limitsCacheTTLMinutesBinding, in: 1...120) {
                        Text("\(viewModel.limitsCacheTTLMinutes) min")
                            .font(.caption.weight(.semibold))
                    }
                }

                HStack(spacing: 8) {
                    ActionPillButton(title: "Open Config Directory", symbol: "folder.fill") {
                        viewModel.openMulticodexConfigDirectory()
                    }

                    ActionPillButton(title: "Refresh Live", symbol: "bolt.horizontal.fill", role: .primary) {
                        viewModel.refreshLive()
                    }
                }
            }
        }
    }

    // MARK: - Advanced Page

    var advancedPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro(
                    title: "Diagnostics",
                    description: "Low-level runtime checks and maintenance tools."
                )

                settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)

                cliResolutionHintRow

                HStack(spacing: 8) {
                    ActionPillButton(title: "Open Runtime", symbol: "terminal") {
                        viewModel.selectSettingsSection(.runtime)
                    }

                    ActionPillButton(title: "Refresh Live", symbol: "bolt.horizontal.fill", role: .primary) {
                        viewModel.refreshLive()
                    }

                    ActionPillButton(title: "Open Config Directory", symbol: "folder.fill") {
                        viewModel.openMulticodexConfigDirectory()
                    }
                }
            }
        }
    }

    var hiddenAdvancedPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro(
                    title: "Advanced",
                    description: "Currently hidden."
                )

                ActionPillButton(title: "Show Advanced", symbol: "gearshape.2", role: .primary) {
                    viewModel.setAdvancedSettingsVisible(true)
                    viewModel.selectSettingsSection(.advanced)
                }
            }
        }
    }
}
