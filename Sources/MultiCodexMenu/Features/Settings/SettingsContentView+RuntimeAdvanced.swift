import SwiftUI

extension SettingsContentView {
    func accountUsageSection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Usage",
            description: "Review the short-term and weekly budget for this account.",
            tint: .green
        ) {
            HStack(spacing: 10) {
                AccountUsageMetricCard(
                    title: "5h",
                    metric: account.usage.fiveHour,
                    resetDisplayMode: viewModel.resetDisplayMode,
                    progressValue: viewModel.progressValue(for: account.usage.fiveHour)
                )
                AccountUsageMetricCard(
                    title: "weekly",
                    metric: account.usage.weekly,
                    resetDisplayMode: viewModel.resetDisplayMode,
                    progressValue: viewModel.progressValue(for: account.usage.weekly)
                )
            }

            HStack(spacing: 12) {
                settingsInfoRow(symbol: "building.2", text: account.source)
                settingsInfoRow(symbol: "clock", text: "Last used \(account.lastUsedLabel)")
            }
        }
    }

    func accountDangerSection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Danger Zone",
            description: "These actions are permanent. Take a moment before removing an account or deleting its data.",
            tint: .red
        ) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Removing an account disconnects it from MultiCodex. Deleting data also clears its stored files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Remove account", role: .destructive) {
                            viewModel.beginAccountRemoval(named: account.name, deleteData: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Remove + delete data", role: .destructive) {
                            viewModel.beginAccountRemoval(named: account.name, deleteData: true)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Reveal destructive actions", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    var runtimePage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionIntro(
                    eyebrow: "Runtime",
                    title: "Make sure the Codex CLI resolves cleanly",
                    description: "Choose a custom binary when needed, or let MultiCodex auto-detect the runtime from known locations and your PATH."
                )

                settingsInsetPanel(
                    title: "Runtime Status",
                    description: "This reflects the current probe result used by the app.",
                    tint: runtimeStatus.color
                ) {
                    settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)

                    if let probe = viewModel.runtimeProbeSummary {
                        Text(probe)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsInsetPanel(
                    title: "Custom Path",
                    description: "Use a specific executable only if the default auto-detection picks the wrong one.",
                    tint: .accentColor
                ) {
                    TextField("/opt/homebrew/bin/codex", text: $codexPathDraft)
                        .textFieldStyle(.roundedBorder)

                    Text("Leave this empty to auto-detect `codex` from known paths or from your shell PATH.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
    }

    var displayPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionIntro(
                    eyebrow: "Display",
                    title: "Keep the interface readable and predictable",
                    description: "These preferences change how status and usage information is presented throughout the menu and settings surfaces."
                )

                settingsInsetPanel(
                    title: "Information Density",
                    description: "Choose how compact or roomy the menu should feel.",
                    tint: .accentColor
                ) {
                    settingsFormRow("Menu density", detail: "Comfortable spacing is easier to scan; compact shows more in less space.") {
                        Picker("Menu density", selection: menuDensityBinding) {
                            ForEach(MenuDensity.allCases) { density in
                                Text(density.title).tag(density)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    settingsFormRow("Reset labels", detail: "Switch how reset times are described across the interface.") {
                        ActionPillButton(title: viewModel.resetDisplayMode.buttonLabel, symbol: "clock") {
                            viewModel.toggleResetDisplayMode()
                        }
                    }
                }

                settingsInsetPanel(
                    title: "Usage Visualization",
                    description: "Pick whether bars emphasize remaining capacity or usage consumed.",
                    tint: .green
                ) {
                    settingsFormRow("Usage bar mode", detail: viewModel.usageBarStyle.descriptionText) {
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

    var troubleshootingPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionIntro(
                    eyebrow: "Troubleshooting",
                    title: "Quick fixes and diagnostics",
                    description: "Use these controls when the runtime looks wrong, cached limits seem stale, or you want to inspect the local config."
                )

                settingsInsetPanel(
                    title: "Resolution Details",
                    description: "Helpful when the app cannot find or execute the Codex CLI.",
                    tint: .orange
                ) {
                    if let hint = viewModel.cliResolutionHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Run a refresh to capture the latest command resolution details.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsInsetPanel(
                    title: "Cache Policy",
                    description: "Controls how often usage limits are refreshed automatically.",
                    tint: .accentColor
                ) {
                    settingsFormRow("Cache TTL", detail: "Lower values favor fresher data. Higher values reduce refresh frequency.") {
                        Stepper(value: limitsCacheTTLMinutesBinding, in: 1...120) {
                            Text("\(viewModel.limitsCacheTTLMinutes) min")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                settingsInsetPanel(
                    title: "Actions",
                    description: "Open the app config directory or force a live refresh when you need fresh diagnostics.",
                    tint: .green
                ) {
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
    }

    var advancedPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        eyebrow: "Advanced",
                        title: "Low-level controls for debugging and isolation",
                        description: "These tools are intentionally separated from everyday settings so the main flow stays clean."
                    )

#if DEBUG
                    settingsInsetPanel(
                        title: "Test Setup",
                        description: "Switch between the real config directory and an isolated temporary sandbox.",
                        tint: .orange
                    ) {
                        Toggle(isOn: testConfigToggleBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use Test Config Directory")
                                    .font(.subheadline.weight(.semibold))
                                Text("Safer for debugging account flows without touching your real local configuration.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .disabled(isAccountActionRunning)

                        if viewModel.isUsingTemporaryAuthSandbox {
                            HStack(spacing: 8) {
                                AccountStatusPill(text: "Using Test Config", color: .orange)

                                if let sandbox = viewModel.temporaryAuthSandboxHome, !sandbox.isEmpty {
                                    Text("\(sandbox)/.config/multicodex")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            HStack(spacing: 8) {
                                ActionPillButton(title: "Reset Sandbox", symbol: "arrow.clockwise") {
                                    viewModel.resetTemporaryAuthSandbox()
                                }
                                .disabled(isAccountActionRunning)

                                ActionPillButton(title: "Open Folder", symbol: "folder") {
                                    viewModel.openTemporaryAuthSandboxDirectory()
                                }

                                ActionPillButton(title: "Use Real Config", symbol: "xmark.circle") {
                                    viewModel.setTemporaryAuthSandboxEnabled(false)
                                }
                                .disabled(isAccountActionRunning)
                            }
                        } else {
                            settingsInfoRow(symbol: "house", text: "Currently using the real config at ~/.config/multicodex")
                        }
                    }
#else
                    settingsInsetPanel(
                        title: "Unavailable in Release Builds",
                        description: "Advanced test tooling is only exposed in debug builds.",
                        tint: .secondary
                    ) {
                        settingsInfoRow(symbol: "lock.fill", text: "Nothing else to configure here right now.")
                    }
#endif
                }
            }
        }
    }

    var hiddenAdvancedPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionIntro(
                    eyebrow: "Advanced",
                    title: "Advanced controls are hidden",
                    description: "Keep the main settings focused, and reveal advanced tools only when you need debugging or test-only options."
                )

                ActionPillButton(title: "Show Advanced", symbol: "gearshape.2", role: .primary) {
                    viewModel.setAdvancedSettingsVisible(true)
                    viewModel.selectSettingsSection(.advanced)
                }
            }
        }
    }

    var removalConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let request = viewModel.pendingAccountRemovalRequest {
                Text(request.deleteData ? "Remove account and delete data" : "Remove account")
                    .font(.title3.weight(.semibold))

                Text(
                    request.deleteData
                        ? "This permanently removes \(request.accountName) and deletes its stored local data."
                        : "This removes \(request.accountName) from MultiCodex but leaves its data intact."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if request.deleteData {
                    settingsInfoRow(symbol: "exclamationmark.triangle.fill", text: "Type \"\(request.accountName)\" to confirm the destructive action.", color: .red)

                    TextField("Account name", text: $deleteConfirmationName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()

                    Button("Cancel") {
                        deleteConfirmationName = ""
                        viewModel.cancelPendingAccountRemoval()
                    }

                    Button(request.deleteData ? "Delete Data" : "Remove", role: .destructive) {
                        viewModel.executePendingAccountRemoval(confirming: deleteConfirmationName)
                        if viewModel.pendingAccountRemovalRequest == nil {
                            deleteConfirmationName = ""
                        }
                    }
                    .disabled(!canConfirmRemoval(request))
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(width: 430)
        .background(settingsBackground)
    }

    func canConfirmRemoval(_ request: PendingAccountRemovalRequest) -> Bool {
        if isAccountActionRunning {
            return false
        }
        if request.deleteData {
            return deleteConfirmationName.trimmingCharacters(in: .whitespacesAndNewlines) == request.accountName
        }
        return true
    }

    func feedbackRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)

            Spacer()

            Button("Dismiss") {
                viewModel.clearAccountActionFeedback()
            }
            .buttonStyle(.plain)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.14), lineWidth: 1)
        )
    }
}
