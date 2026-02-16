import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var viewModel: UsageMenuViewModel

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
            codexPathDraft = viewModel.customNodePath
            syncRenameDrafts()
            if viewModel.selectedSettingsSection == .advanced, !viewModel.isAdvancedSettingsVisible {
                viewModel.setAdvancedSettingsVisible(true)
            }
        }
        .onChange(of: viewModel.customNodePath) { codexPathDraft = $0 }
        .onChange(of: viewModel.profiles.map(\.name)) { _ in
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
                case .profiles:
                    profilesPage
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

                Text("Manage profiles, runtime setup, display preferences, and troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = viewModel.refreshWarningMessage {
                    subtleWarningRow(warning)
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
                        dashboardMetric(title: "Profiles", value: "\(viewModel.profiles.count)")
                        dashboardMetric(title: "Needs Login", value: "\(viewModel.profilesNeedingLogin.count)")
                        dashboardMetric(title: "Current", value: viewModel.currentProfile?.name ?? "-")
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
            Image(systemName: alertSymbol(for: alert.severity))
                .font(.caption.weight(.semibold))
                .foregroundStyle(alertColor(for: alert.severity))

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(alertColor(for: alert.severity))
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
        .background(alertColor(for: alert.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(alertColor(for: alert.severity).opacity(0.22), lineWidth: 1)
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
                        ActionPillButton(title: "Login First Profile", symbol: "person.crop.circle.badge.plus", role: .primary) {
                            viewModel.startNewProfileLogin()
                        }
                    case .verify:
                        ActionPillButton(title: "Check Status", symbol: "person.crop.circle.badge.checkmark", role: .primary) {
                            if let current = viewModel.currentProfile {
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

    private var profilesPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Profiles")
                        .font(.headline)

                    Spacer()

                    ActionPillButton(title: "Login New Profile", symbol: "person.crop.circle.badge.plus", role: .primary, isDisabled: isProfileActionRunning) {
                        viewModel.startNewProfileLogin()
                    }
                }

                if let message = viewModel.profileActionMessage {
                    feedbackRow(message, color: .green)
                }

                if let error = viewModel.profileActionError {
                    feedbackRow(error, color: .red)
                }

                if viewModel.profiles.isEmpty {
                    noProfilesState
                } else {
                    HStack(spacing: 0) {
                        profileListPane
                            .frame(width: 260)

                        Divider()
                            .padding(.horizontal, 12)

                        profileDetailPane
                    }
                    .frame(minHeight: 380)
                }
            }
        }
    }

    private var noProfilesState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No profiles yet", systemImage: "person.crop.circle.badge.plus")
                .font(.caption.weight(.semibold))

            Text("Use \"Login New Profile\" to connect your first account.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: runtimeStatusSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(runtimeStatusColor)
                Text(runtimeStatusText)
                    .font(.caption2)
                    .foregroundStyle(viewModel.isCodexRuntimeAvailable ? .secondary : runtimeStatusColor)
                    .lineLimit(2)
            }
        }
    }

    private var profileListPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search profiles", text: profileSearchBinding)
                .textFieldStyle(.roundedBorder)

            if viewModel.filteredProfiles.isEmpty {
                Text("No profiles match your search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.filteredProfiles) { profile in
                            Button {
                                viewModel.selectSettingsProfile(named: profile.name)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(profile.connectionState.label)
                                            .font(.caption2)
                                            .foregroundStyle(statusColor(for: profile.connectionState))
                                    }

                                    Spacer()

                                    if profile.isCurrent {
                                        pill("Current", color: .accentColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelectedProfile(profile.name) ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isSelectedProfile(profile.name) ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.10), lineWidth: 1)
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
    private var profileDetailPane: some View {
        if let profile = viewModel.selectedSettingsProfile {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    profileIdentitySection(profile)
                    profileAuthSection(profile)
                    profileUsageSection(profile)
                    profileDangerSection(profile)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select a profile")
                    .font(.headline)
                Text("Choose a profile from the left to manage it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func profileIdentitySection(_ profile: ProfileUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Identity")

            Text(profile.name)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Rename profile", text: renameBinding(for: profile.name))
                    .textFieldStyle(.roundedBorder)

                ActionPillButton(title: "Rename", symbol: "pencil") {
                    viewModel.renameProfile(from: profile.name, to: renameDrafts[profile.name] ?? profile.name)
                }
                .disabled(cannotRename(profile.name) || isProfileActionRunning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func profileAuthSection(_ profile: ProfileUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Authentication")

            HStack(spacing: 8) {
                if !profile.isCurrent {
                    ActionPillButton(title: "Use", symbol: "checkmark.circle.fill", role: .secondary) {
                        viewModel.switchToProfile(named: profile.name)
                    }
                    .disabled(isProfileActionRunning)
                }

                ActionPillButton(
                    title: profile.connectionState == .needsLogin ? "Re-login" : "Login",
                    symbol: "person.crop.circle.badge.plus",
                    role: .secondary
                ) {
                    viewModel.openLoginInTerminal(for: profile.name)
                }
                .disabled(isProfileActionRunning)

                ActionPillButton(title: "Status", symbol: "person.crop.circle.badge.checkmark") {
                    viewModel.checkLoginStatus(for: profile.name)
                }
                .disabled(isProfileActionRunning)

                ActionPillButton(title: "Import Auth", symbol: "square.and.arrow.down") {
                    viewModel.importCurrentAuth(into: profile.name)
                }
                .disabled(isProfileActionRunning)
            }

            if let hint = profile.connectionHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(statusColor(for: profile.connectionState))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func profileUsageSection(_ profile: ProfileUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Usage")

            HStack(spacing: 8) {
                SettingsUsageMetricView(
                    metric: profile.usage.fiveHour,
                    title: "5h",
                    resetDisplayMode: viewModel.resetDisplayMode,
                    progressValue: viewModel.progressValue(for: profile.usage.fiveHour)
                )
                SettingsUsageMetricView(
                    metric: profile.usage.weekly,
                    title: "weekly",
                    resetDisplayMode: viewModel.resetDisplayMode,
                    progressValue: viewModel.progressValue(for: profile.usage.weekly)
                )
            }

            HStack(spacing: 8) {
                Text(profile.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Last used \(profile.lastUsedLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func profileDangerSection(_ profile: ProfileUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These actions are permanent and cannot be undone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Remove profile", role: .destructive) {
                            viewModel.beginProfileRemoval(named: profile.name, deleteData: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Remove + delete data", role: .destructive) {
                            viewModel.beginProfileRemoval(named: profile.name, deleteData: true)
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
                        viewModel.updateCustomNodePath(codexPathDraft)
                    }
                    .disabled(normalized(codexPathDraft) == viewModel.customNodePath)

                    ActionPillButton(title: "Choose", symbol: "folder") {
                        viewModel.chooseCustomNodePath()
                    }

                    ActionPillButton(title: "Use Auto", symbol: "sparkles") {
                        codexPathDraft = ""
                        viewModel.clearCustomNodePath()
                    }
                    .disabled(viewModel.customNodePath.isEmpty)
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
                    .disabled(isProfileActionRunning)

                    if viewModel.isUsingTemporaryAuthSandbox {
                        pill("Using Test Config", color: .orange)

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
                            .disabled(isProfileActionRunning)

                            ActionPillButton(title: "Open Folder", symbol: "folder") {
                                viewModel.openTemporaryAuthSandboxDirectory()
                            }

                            ActionPillButton(title: "Use Real Config", symbol: "xmark.circle") {
                                viewModel.setTemporaryAuthSandboxEnabled(false)
                            }
                            .disabled(isProfileActionRunning)
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
            if let request = viewModel.pendingProfileRemovalRequest {
                Text(request.deleteData ? "Remove profile and delete data" : "Remove profile")
                    .font(.headline)

                Text(request.deleteData
                    ? "This will permanently remove \(request.profileName) and delete its stored data."
                    : "This will remove \(request.profileName) from MultiCodex.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if request.deleteData {
                    Text("Type \"\(request.profileName)\" to confirm")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    TextField("Profile name", text: $deleteConfirmationName)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        deleteConfirmationName = ""
                        viewModel.cancelPendingProfileRemoval()
                    }

                    Button(request.deleteData ? "Delete Data" : "Remove", role: .destructive) {
                        viewModel.executePendingProfileRemoval(confirming: deleteConfirmationName)
                        if viewModel.pendingProfileRemovalRequest == nil {
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

    private func canConfirmRemoval(_ request: PendingProfileRemovalRequest) -> Bool {
        if isProfileActionRunning {
            return false
        }
        if request.deleteData {
            return deleteConfirmationName.trimmingCharacters(in: .whitespacesAndNewlines) == request.profileName
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
                viewModel.clearProfileActionFeedback()
            }
            .buttonStyle(.plain)
            .font(.caption2)
        }
    }

    private func subtleWarningRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private var profileSearchBinding: Binding<String> {
        Binding(
            get: { viewModel.profileSearchQuery },
            set: { viewModel.setProfileSearchQuery($0) }
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
            get: { viewModel.pendingProfileRemovalRequest != nil },
            set: { isPresented in
                if !isPresented {
                    deleteConfirmationName = ""
                    viewModel.cancelPendingProfileRemoval()
                }
            }
        )
    }

    private var isProfileActionRunning: Bool {
        viewModel.profileActionInFlightName != nil || viewModel.switchingProfileName != nil
    }

    private var runtimeStatusText: String {
        viewModel.runtimeProbeSummary ?? "Checking codex runtime..."
    }

    private var runtimeStatusSymbol: String {
        if viewModel.isCodexRuntimeAvailable {
            return "checkmark.circle.fill"
        }
        if viewModel.runtimeProbeSummary == nil {
            return "clock"
        }
        return "exclamationmark.triangle.fill"
    }

    private var runtimeStatusColor: Color {
        if viewModel.isCodexRuntimeAvailable {
            return .green
        }
        if viewModel.runtimeProbeSummary == nil {
            return .secondary
        }
        return .orange
    }

    private var testConfigToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isUsingTemporaryAuthSandbox },
            set: { viewModel.setTemporaryAuthSandboxEnabled($0) }
        )
    }

    private func renameBinding(for profileName: String) -> Binding<String> {
        Binding(
            get: { renameDrafts[profileName] ?? profileName },
            set: { renameDrafts[profileName] = $0 }
        )
    }

    private func cannotRename(_ profileName: String) -> Bool {
        let raw = renameDrafts[profileName] ?? profileName
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == profileName
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncRenameDrafts() {
        let names = Set(viewModel.profiles.map(\.name))
        renameDrafts = renameDrafts.filter { names.contains($0.key) }
        for profile in viewModel.profiles where renameDrafts[profile.name] == nil {
            renameDrafts[profile.name] = profile.name
        }
    }

    private func isSelectedProfile(_ name: String) -> Bool {
        viewModel.selectedSettingsProfileName == name
    }

    private func statusColor(for state: ProfileConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .needsLogin:
            return .orange
        case .error:
            return .red
        }
    }

    private func alertColor(for severity: MenuAlertState.Severity) -> Color {
        switch severity {
        case .runtimeUnavailable:
            return .orange
        case .refreshError:
            return .red
        case .authRequired:
            return .orange
        }
    }

    private func alertSymbol(for severity: MenuAlertState.Severity) -> String {
        switch severity {
        case .runtimeUnavailable:
            return "terminal"
        case .refreshError:
            return "exclamationmark.triangle.fill"
        case .authRequired:
            return "person.crop.circle.badge.exclamationmark"
        }
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

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct SettingsPanelCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct SettingsUsageMetricView: View {
    let metric: UsageMetric
    let title: String
    let resetDisplayMode: ResetDisplayMode
    let progressValue: Double

    private var tone: Color {
        switch UsageLevel.from(usedPercent: metric.usedPercent) {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .normal:
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(metric.percentText)
                    .font(.caption.weight(.semibold))
            }

            ProgressView(value: progressValue)
                .tint(tone)

            Text(metric.resetText(mode: resetDisplayMode))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
