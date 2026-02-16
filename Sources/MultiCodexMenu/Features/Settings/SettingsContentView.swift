import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel

    @State private var codexPathDraft = ""
    @State private var renameDrafts: [String: String] = [:]
    @State private var deleteConfirmationName = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            codexPathDraft = viewModel.customCodexPath
            syncRenameDrafts()
            if viewModel.selectedSettingsSection == .advanced, !viewModel.isAdvancedSettingsVisible {
                viewModel.setAdvancedSettingsVisible(true)
            }
        }
        .onChange(of: viewModel.customCodexPath) { codexPathDraft = $0 }
        .onChange(of: viewModel.accounts.map(\.name)) { _ in
            syncRenameDrafts()
        }
        .sheet(isPresented: removalSheetBinding) {
            removalConfirmationSheet
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: sidebarSelectionBinding) {
                ForEach(viewModel.settingsSections) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }

            Divider()

            HStack {
                if viewModel.isAdvancedSettingsVisible {
                    Button("Hide Advanced") {
                        viewModel.setAdvancedSettingsVisible(false)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                } else {
                    Button("Show Advanced") {
                        viewModel.setAdvancedSettingsVisible(true)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                Spacer()
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard

                switch viewModel.selectedSettingsSection {
                case .dashboard:
                    dashboardPage
                case .accounts:
                    accountsPage
                case .runtime:
                    runtimePage
                case .display:
                    displayPage
                case .troubleshooting:
                    troubleshootingPage
                case .advanced:
                    if viewModel.isAdvancedSettingsVisible {
                        advancedPage
                    } else {
                        hiddenAdvancedPage
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var headerCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.title3.weight(.semibold))

                Text("Manage accounts, runtime setup, display preferences, and troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = viewModel.refreshWarningMessage {
                    SubtleWarningRow(text: warning)
                }

                HStack(spacing: 8) {
                    ActionPillButton(
                        title: "Refresh",
                        symbol: "arrow.clockwise",
                        role: .secondary,
                        layout: .iconOnly
                    ) {
                        viewModel.refresh()
                    }

                    ActionPillButton(title: "Refresh Live", symbol: "bolt.horizontal.fill", role: .secondary) {
                        viewModel.refreshLive()
                    }
                }
            }
        }
    }

    private var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dashboard")
                        .font(.headline)

                    HStack(spacing: 12) {
                        dashboardMetric(title: "Accounts", value: "\(viewModel.accounts.count)")
                        dashboardMetric(title: "Needs Login", value: "\(viewModel.accountsNeedingLogin.count)")
                        dashboardMetric(title: "Current", value: viewModel.currentAccount?.name ?? "-")
                    }

                    if let alert = viewModel.prioritizedMenuAlert {
                        dashboardAlert(alert)
                    }
                }
            }

            if !viewModel.onboardingState.isComplete {
                onboardingWizardCard
            }
        }
    }

    private func dashboardMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func dashboardAlert(_ alert: MenuAlertState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: AccountPresentation.alertSymbol(for: alert.severity))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AccountPresentation.alertColor(for: alert.severity))

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AccountPresentation.alertColor(for: alert.severity))
                Text(alert.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ActionPillButton(title: alert.actionTitle, symbol: "arrow.right.circle.fill", role: .primary) {
                handleAlertAction(alert)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AccountPresentation.alertColor(for: alert.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AccountPresentation.alertColor(for: alert.severity).opacity(0.22), lineWidth: 1)
        )
    }

    private var onboardingWizardCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("First-Run Setup")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    onboardingStepRow(.runtime, isActive: viewModel.onboardingState.step == .runtime)
                    onboardingStepRow(.login, isActive: viewModel.onboardingState.step == .login)
                    onboardingStepRow(.verify, isActive: viewModel.onboardingState.step == .verify)
                    onboardingStepRow(.done, isActive: viewModel.onboardingState.step == .done)
                }

                HStack(spacing: 8) {
                    switch viewModel.onboardingState.step {
                    case .runtime:
                        ActionPillButton(title: "Open Runtime", symbol: "terminal", role: .primary) {
                            viewModel.selectSettingsSection(.runtime)
                        }
                    case .login:
                        ActionPillButton(title: "Login First Account", symbol: "person.crop.circle.badge.plus", role: .primary) {
                            viewModel.startNewAccountLogin()
                        }
                    case .verify:
                        ActionPillButton(title: "Check Status", symbol: "person.crop.circle.badge.checkmark", role: .primary) {
                            if let current = viewModel.currentAccount {
                                viewModel.checkLoginStatus(for: current.name)
                            } else {
                                viewModel.refreshLive()
                            }
                        }
                    case .done:
                        ActionPillButton(title: "Finish", symbol: "checkmark.circle.fill", role: .primary) {
                            viewModel.markOnboardingCompleted()
                        }
                    }

                    ActionPillButton(title: "Reset Wizard", symbol: "arrow.counterclockwise") {
                        viewModel.resetOnboardingProgress()
                    }
                }
            }
        }
    }

    private func onboardingStepRow(_ step: OnboardingStep, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: stepSymbol(step, isActive: isActive))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

            Text(step.title)
                .font(.caption)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            Spacer()
        }
    }

    private var accountsPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Accounts")
                        .font(.headline)

                    Spacer()

                    ActionPillButton(title: "Login New Account", symbol: "person.crop.circle.badge.plus", role: .primary, isDisabled: isAccountActionRunning) {
                        viewModel.startNewAccountLogin()
                    }
                }

                if let message = viewModel.accountActionMessage {
                    feedbackRow(message, color: .green)
                }

                if let error = viewModel.accountActionError {
                    feedbackRow(error, color: .red)
                }

                if viewModel.accounts.isEmpty {
                    noAccountsState
                } else {
                    HStack(spacing: 0) {
                        accountListPane
                            .frame(width: 260)

                        Divider()
                            .padding(.horizontal, 12)

                        accountDetailPane
                    }
                    .frame(minHeight: 380)
                }
            }
        }
    }

    private var noAccountsState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No accounts yet", systemImage: "person.crop.circle.badge.plus")
                .font(.caption.weight(.semibold))

            Text("Use \"Login New Account\" to connect your first account.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: runtimeStatus.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(runtimeStatus.color)
                Text(runtimeStatus.text)
                    .font(.caption2)
                    .foregroundStyle(viewModel.isCodexRuntimeAvailable ? .secondary : runtimeStatus.color)
                    .lineLimit(2)
            }
        }
    }

    private var accountListPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search accounts", text: accountSearchBinding)
                .textFieldStyle(.roundedBorder)

            if viewModel.filteredAccounts.isEmpty {
                Text("No accounts match your search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.filteredAccounts) { account in
                            Button {
                                viewModel.selectSettingsAccount(named: account.name)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.name)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(account.connectionState.label)
                                            .font(.caption2)
                                            .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))
                                    }

                                    Spacer()

                                    if account.isCurrent {
                                        AccountStatusPill(text: "Current", color: .accentColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelectedAccount(account.name) ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isSelectedAccount(account.name) ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.10), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accountDetailPane: some View {
        if let account = viewModel.selectedSettingsAccount {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    accountIdentitySection(account)
                    accountAuthSection(account)
                    accountUsageSection(account)
                    accountDangerSection(account)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select an account")
                    .font(.headline)
                Text("Choose an account from the left to manage it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func accountIdentitySection(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Identity")

            Text(account.name)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Rename account", text: renameBinding(for: account.name))
                    .textFieldStyle(.roundedBorder)

                ActionPillButton(title: "Rename", symbol: "pencil") {
                    viewModel.renameAccount(from: account.name, to: renameDrafts[account.name] ?? account.name)
                }
                .disabled(cannotRename(account.name) || isAccountActionRunning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func accountAuthSection(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Authentication")

            HStack(spacing: 8) {
                if !account.isCurrent {
                    ActionPillButton(title: "Use", symbol: "checkmark.circle.fill", role: .secondary) {
                        viewModel.switchToAccount(named: account.name)
                    }
                    .disabled(isAccountActionRunning)
                }

                ActionPillButton(
                    title: account.connectionState == .needsLogin ? "Re-login" : "Login",
                    symbol: "person.crop.circle.badge.plus",
                    role: .secondary
                ) {
                    viewModel.openLoginInTerminal(for: account.name)
                }
                .disabled(isAccountActionRunning)

                ActionPillButton(title: "Status", symbol: "person.crop.circle.badge.checkmark") {
                    viewModel.checkLoginStatus(for: account.name)
                }
                .disabled(isAccountActionRunning)

                ActionPillButton(title: "Import Auth", symbol: "square.and.arrow.down") {
                    viewModel.importCurrentAuth(into: account.name)
                }
                .disabled(isAccountActionRunning)
            }

            if let hint = account.connectionHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func accountUsageSection(_ account: AccountUsage) -> some View {
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

    private func accountDangerSection(_ account: AccountUsage) -> some View {
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

    private var runtimePage: some View {
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

    private var displayPage: some View {
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

    private var troubleshootingPage: some View {
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

    private var advancedPage: some View {
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

    private var hiddenAdvancedPage: some View {
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

    private var removalConfirmationSheet: some View {
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

    private func canConfirmRemoval(_ request: PendingAccountRemovalRequest) -> Bool {
        if isAccountActionRunning {
            return false
        }
        if request.deleteData {
            return deleteConfirmationName.trimmingCharacters(in: .whitespacesAndNewlines) == request.accountName
        }
        return true
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func feedbackRow(_ text: String, color: Color) -> some View {
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

    private func displayOptionRow<Control: View>(
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

    private var sidebarSelectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { viewModel.selectedSettingsSection },
            set: { newValue in
                guard let newValue else { return }
                viewModel.selectSettingsSection(newValue)
            }
        )
    }

    private var accountSearchBinding: Binding<String> {
        Binding(
            get: { viewModel.accountSearchQuery },
            set: { viewModel.setAccountSearchQuery($0) }
        )
    }

    private var menuDensityBinding: Binding<MenuDensity> {
        Binding(
            get: { viewModel.menuDensity },
            set: { viewModel.setMenuDensity($0) }
        )
    }

    private var usageBarStyleBinding: Binding<UsageBarStyle> {
        Binding(
            get: { viewModel.usageBarStyle },
            set: { viewModel.setUsageBarStyle($0) }
        )
    }

    private var limitsCacheTTLMinutesBinding: Binding<Int> {
        Binding(
            get: { viewModel.limitsCacheTTLMinutes },
            set: { viewModel.setLimitsCacheTTLSeconds($0 * 60) }
        )
    }

    private var removalSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingAccountRemovalRequest != nil },
            set: { isPresented in
                if !isPresented {
                    deleteConfirmationName = ""
                    viewModel.cancelPendingAccountRemoval()
                }
            }
        )
    }

    private var isAccountActionRunning: Bool {
        viewModel.accountActionInFlightName != nil || viewModel.switchingAccountName != nil
    }

    private var runtimeStatus: RuntimeStatusPresentation {
        AccountPresentation.runtimeStatus(
            summary: viewModel.runtimeProbeSummary,
            isAvailable: viewModel.isCodexRuntimeAvailable
        )
    }

    private var testConfigToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isUsingTemporaryAuthSandbox },
            set: { viewModel.setTemporaryAuthSandboxEnabled($0) }
        )
    }

    private func renameBinding(for accountName: String) -> Binding<String> {
        Binding(
            get: { renameDrafts[accountName] ?? accountName },
            set: { renameDrafts[accountName] = $0 }
        )
    }

    private func cannotRename(_ accountName: String) -> Bool {
        let raw = renameDrafts[accountName] ?? accountName
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == accountName
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncRenameDrafts() {
        let names = Set(viewModel.accounts.map(\.name))
        renameDrafts = renameDrafts.filter { names.contains($0.key) }
        for account in viewModel.accounts where renameDrafts[account.name] == nil {
            renameDrafts[account.name] = account.name
        }
    }

    private func isSelectedAccount(_ name: String) -> Bool {
        viewModel.selectedSettingsAccountName == name
    }

    private func stepSymbol(_ step: OnboardingStep, isActive: Bool) -> String {
        if isActive {
            return "circle.fill"
        }
        switch step {
        case .done:
            return "checkmark.circle.fill"
        default:
            return "circle"
        }
    }

    private func handleAlertAction(_ alert: MenuAlertState) {
        switch alert.action {
        case .openRuntimeSettings:
            viewModel.selectSettingsSection(.runtime)
        default:
            viewModel.performMenuAlertAction(alert.action)
        }
    }
}
