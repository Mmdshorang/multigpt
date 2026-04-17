import SwiftUI

extension SettingsContentView {
    var systemPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Runtime",
                        description: "Codex CLI configuration",
                        symbol: "terminal.fill"
                    )

                    HStack(spacing: 8) {
                        Image(systemName: runtimeStatus.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(runtimeStatus.color)

                        Text(runtimeStatus.text)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(runtimeStatus.color)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(runtimeStatus.color.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(runtimeStatus.color.opacity(0.15), lineWidth: 1)
                    )

                    HStack(spacing: 8) {
                        SettingsTextField(
                            placeholder: "/opt/homebrew/bin/codex",
                            text: $codexPathDraft
                        )

                        ActionPillButton(title: "Choose", symbol: "folder") {
                            viewModel.chooseCustomCodexPath()
                        }
                    }

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

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Diagnostics",
                        description: "System information and tools",
                        symbol: "stethoscope"
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

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Cache",
                        description: "Data refresh interval",
                        symbol: "timer"
                    )

                    settingsFormRow("Refresh interval", icon: "arrow.triangle.2.circlepath") {
                        Stepper(value: limitsCacheTTLMinutesBinding, in: 1...120) {
                            Text("\(viewModel.limitsCacheTTLMinutes) min")
                                .font(DashboardTokens.Font.metadata().weight(.semibold))
                                .foregroundStyle(DashboardTokens.textPrimary)
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
