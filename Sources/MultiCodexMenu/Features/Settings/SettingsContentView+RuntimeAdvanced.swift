import SwiftUI

extension SettingsContentView {
    func accountUsageSection(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Usage")

            HStack(spacing: 8) {
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

            HStack(spacing: 8) {
                Text(account.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Last used \(account.lastUsedLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func accountDangerSection(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These actions are permanent and cannot be undone.")
                        .font(.caption2)
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
                .padding(.top, 6)
            } label: {
                Label("Danger Zone", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        )
    }

    var runtimePage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runtime")
                    .font(.headline)

                TextField("/opt/homebrew/bin/codex", text: $codexPathDraft)
                    .textFieldStyle(.roundedBorder)

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

                if let probe = viewModel.runtimeProbeSummary {
                    Text(probe)
                        .font(.caption2)
                        .foregroundStyle(viewModel.isCodexRuntimeAvailable ? Color.secondary : Color.orange)
                        .lineLimit(3)
                }

                Text("Leave empty to auto-detect codex from known paths or PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var displayPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Display")
                    .font(.headline)

                displayOptionRow("Reset labels") {
                    ActionPillButton(title: viewModel.resetDisplayMode.buttonLabel, symbol: "clock") {
                        viewModel.toggleResetDisplayMode()
                    }
                }

                displayOptionRow("Menu density") {
                    Picker("Menu density", selection: menuDensityBinding) {
                        ForEach(MenuDensity.allCases) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                displayOptionRow("Usage bar mode") {
                    Picker("Usage bars", selection: usageBarStyleBinding) {
                        ForEach(UsageBarStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                Text(viewModel.usageBarStyle.descriptionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var troubleshootingPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Troubleshooting")
                    .font(.headline)

                if let hint = viewModel.cliResolutionHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                } else {
                    Text("Run refresh to capture command resolution details.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                displayOptionRow("Cache TTL") {
                    Stepper(value: limitsCacheTTLMinutesBinding, in: 1...120) {
                        Text("\(viewModel.limitsCacheTTLMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }

                Text("Controls cached limits freshness and auto-refresh cadence.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ActionPillButton(title: "Open Config Directory", symbol: "folder.fill") {
                        viewModel.openMulticodexConfigDirectory()
                    }

                    ActionPillButton(title: "Refresh Live", symbol: "bolt.horizontal.fill", role: .secondary) {
                        viewModel.refreshLive()
                    }
                }
            }
        }
    }

    var advancedPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Advanced")
                        .font(.headline)

                    Text("Advanced diagnostics and test tooling are available below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

#if DEBUG
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Test Setup")
                        .font(.headline)

                    Toggle(isOn: testConfigToggleBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Test Config Directory")
                                .font(.subheadline.weight(.semibold))
                            Text("Toggle between real and isolated temporary config directories.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(isAccountActionRunning)

                    if viewModel.isUsingTemporaryAuthSandbox {
                        AccountStatusPill(text: "Using Test Config", color: .orange)

                        if let sandbox = viewModel.temporaryAuthSandboxHome, !sandbox.isEmpty {
                            Text("Current: \(sandbox)/.config/multicodex")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
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
                        Text("Current: real config at ~/.config/multicodex")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
#endif
        }
    }

    var hiddenAdvancedPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Advanced")
                    .font(.headline)

                Text("Advanced controls are hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ActionPillButton(title: "Show Advanced", symbol: "gearshape.2", role: .secondary) {
                    viewModel.setAdvancedSettingsVisible(true)
                    viewModel.selectSettingsSection(.advanced)
                }
            }
        }
    }

    var removalConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let request = viewModel.pendingAccountRemovalRequest {
                Text(request.deleteData ? "Remove account and delete data" : "Remove account")
                    .font(.headline)

                Text(request.deleteData
                    ? "This will permanently remove \(request.accountName) and delete its stored data."
                    : "This will remove \(request.accountName) from MultiCodex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if request.deleteData {
                    Text("Type \"\(request.accountName)\" to confirm")
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
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(width: 420)
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

    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    func feedbackRow(_ text: String, color: Color) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(color)
            Spacer()
            Button("Dismiss") {
                viewModel.clearAccountActionFeedback()
            }
            .buttonStyle(.plain)
            .font(.caption2)
        }
    }

    func displayOptionRow<Control: View>(
        _ label: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Spacer(minLength: 0)

            control()
                .frame(width: 220, alignment: .leading)
        }
    }
}
