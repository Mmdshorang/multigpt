import SwiftUI

// MARK: - System Page
// Merges Runtime + Troubleshooting + Advanced

extension SettingsContentView {
    var systemPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Runtime Status Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Runtime",
                        description: "Codex CLI configuration"
                    )

                    // Status row
                    HStack(spacing: 8) {
                        Image(systemName: runtimeStatus.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(runtimeStatus.color)

                        Text(runtimeStatus.text)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(runtimeStatus.color)
                    }

                    // Path input
                    HStack(spacing: 8) {
                        TextField("/opt/homebrew/bin/codex", text: $codexPathDraft)
                            .textFieldStyle(.roundedBorder)

                        ActionPillButton(title: "Choose", symbol: "folder") {
                            viewModel.chooseCustomCodexPath()
                        }
                    }

                    // Action buttons
                    HStack(spacing: 8) {
                        ActionPillButton(title: "Save", symbol: "checkmark", role: .primary) {
                            viewModel.updateCustomCodexPath(codexPathDraft)
                        }
                        .disabled(normalized(codexPathDraft) == viewModel.customCodexPath)

                        ActionPillButton(title: "Auto", symbol: "sparkles") {
                            codexPathDraft = ""
                            viewModel.clearCustomCodexPath()
                        }
                        .disabled(viewModel.customCodexPath.isEmpty)
                    }

                    if let probe = viewModel.runtimeProbeSummary, !probe.isEmpty {
                        Text(probe)
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Diagnostics Card (collapsible)
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Diagnostics",
                        description: "System information and tools"
                    )

                    HStack(spacing: 8) {
                        ActionPillButton(title: "Open Config", symbol: "folder.fill") {
                            viewModel.openMulticodexConfigDirectory()
                        }

                        ActionPillButton(title: "Refresh Live", symbol: "bolt.horizontal.fill", role: .primary) {
                            viewModel.refreshLive()
                        }
                    }

                    if let hint = viewModel.cliResolutionHint {
                        Text(hint)
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Run a refresh to capture command resolution details.")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                    }
                }
            }

            // Cache Settings Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Cache",
                        description: "Data refresh interval"
                    )

                    HStack(spacing: 12) {
                        Text("Refresh interval")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textPrimary)

                        Spacer()

                        Stepper(value: limitsCacheTTLMinutesBinding, in: 1...120) {
                            Text("\(viewModel.limitsCacheTTLMinutes) min")
                                .font(DashboardTokens.Font.metadata().weight(.semibold))
                                .foregroundStyle(DashboardTokens.textPrimary)
                                .frame(minWidth: 50, alignment: .trailing)
                        }
                    }

                    Text("Lower values update more frequently but may impact performance.")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                }
            }
        }
    }
}
