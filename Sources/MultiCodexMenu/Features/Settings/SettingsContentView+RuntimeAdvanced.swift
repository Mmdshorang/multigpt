import SwiftUI

extension SettingsContentView {
    func accountUsageSection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Usage",
            description: "Current usage for this account."
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

            settingsInfoRow(symbol: "clock", text: "Last used \(account.lastUsedLabel)")
        }
    }

    func accountDangerSection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Danger Zone",
            description: "Permanent actions for this account."
        ) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Removing an account disconnects it from MultiCodex. Deleting data also clears stored files.")
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
                Label("Show destructive actions", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    var runtimePage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionIntro(
                    title: "Runtime",
                    description: "Choose a custom Codex CLI path or use automatic detection."
                )

                settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)

                TextField("/opt/homebrew/bin/codex", text: $codexPathDraft)
                    .textFieldStyle(.roundedBorder)

                if let probe = viewModel.runtimeProbeSummary {
                    Text(probe)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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

    var displayPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionIntro(
                    title: "Display",
                    description: "Adjust how usage and status information is shown."
                )

                settingsFormRow("Menu density", detail: "Choose how compact the menu should feel.") {
                    Picker("Menu density", selection: menuDensityBinding) {
                        ForEach(MenuDensity.allCases) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                settingsFormRow("Reset labels", detail: "Switch how reset times are described.") {
                    ActionPillButton(title: viewModel.resetDisplayMode.buttonLabel, symbol: "clock") {
                        viewModel.toggleResetDisplayMode()
                    }
                }

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

    var troubleshootingPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionIntro(
                    title: "Troubleshooting",
                    description: "Use these controls when runtime resolution or cached data needs attention."
                )

                if let hint = viewModel.cliResolutionHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Run a refresh to capture command resolution details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

    var advancedPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionIntro(
                    title: "Advanced",
                    description: "Debug and sandbox controls live here when you need them."
                )

#if DEBUG
                Toggle(isOn: testConfigToggleBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Test Config Directory")
                            .font(.subheadline.weight(.semibold))
                        Text("Toggle between the real config directory and an isolated temporary sandbox.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .disabled(isAccountActionRunning)

                if viewModel.isUsingTemporaryAuthSandbox {
                    if let sandbox = viewModel.temporaryAuthSandboxHome, !sandbox.isEmpty {
                        settingsInfoRow(symbol: "folder", text: "\(sandbox)/.config/multicodex")
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
#else
                Text("Advanced test tooling is only available in debug builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
#endif
            }
        }
    }

    var hiddenAdvancedPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 14) {
                settingsSectionIntro(
                    title: "Advanced",
                    description: "Advanced controls are hidden until you choose to show them."
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
                    .font(.headline)

                Text(
                    request.deleteData
                        ? "This permanently removes \(request.accountName) and deletes its stored local data."
                        : "This removes \(request.accountName) from MultiCodex but leaves its data intact."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if request.deleteData {
                    Text("Type \"\(request.accountName)\" to confirm.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

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
            }
        }
        .padding(18)
        .frame(width: 430)
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
    }
}
