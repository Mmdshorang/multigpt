import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var viewModel: UsageMenuViewModel
    @State private var codexPathDraft = ""
    @State private var renameDrafts: [String: String] = [:]
    @State private var selectedTab: SettingsTab = .profiles
    @State private var isDiagnosticsExpanded = false

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case profiles = "Profiles"
        case runtime = "Runtime"
        case advanced = "Advanced"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerCard
                    tabSelector
                    tabContent
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            codexPathDraft = viewModel.customNodePath
            syncRenameDrafts()
        }
        .onChange(of: viewModel.customNodePath) { codexPathDraft = $0 }
        .onChange(of: viewModel.profiles.map(\.name)) { _ in
            syncRenameDrafts()
        }
    }

    private var headerCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.title3.weight(.semibold))

                Text("Manage profiles, runtime setup, and advanced troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    simpleActionButton("Refresh", symbol: "arrow.clockwise") {
                        viewModel.refresh()
                    }

                    simpleActionButton("Refresh Live", symbol: "bolt.horizontal.fill", prominent: true) {
                        viewModel.refreshLive()
                    }
                }
            }
        }
    }

    private var tabSelector: some View {
        Picker("Settings Tab", selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .profiles:
            profilesCard
        case .runtime:
            runtimeCard
            preferencesCard
        case .advanced:
            diagnosticsCard
#if DEBUG
            testSetupCard
#endif
        }
    }

    private var profilesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Profiles")
                    .font(.headline)

                simpleActionButton("Login New Profile", symbol: "person.crop.circle.badge.plus", prominent: true) {
                    viewModel.startNewProfileLogin()
                }
                .disabled(isProfileActionRunning)

                if let message = viewModel.profileActionMessage {
                    feedbackRow(message, color: .green)
                }

                if let error = viewModel.profileActionError {
                    feedbackRow(error, color: .red)
                }

                if viewModel.profiles.isEmpty {
                    emptyProfilesOnboarding
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.profiles) { profile in
                            profileRow(profile)
                        }
                    }
                }
            }
        }
    }

    private var emptyProfilesOnboarding: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No profiles yet", systemImage: "person.crop.circle.badge.plus")
                .font(.caption.weight(.semibold))

            Text("Use “Login New Profile” to connect your first account.")
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
        .padding(.vertical, 4)
    }

    private func profileRow(_ profile: ProfileUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))

                if profile.isCurrent {
                    pill("Current", color: .accentColor)
                }
                pill(profile.connectionState.label, color: statusColor(for: profile.connectionState))

                Spacer(minLength: 8)

                if viewModel.profileActionInFlightName == profile.name {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                if !profile.isCurrent {
                    simpleActionButton("Use", symbol: "checkmark.circle.fill", prominent: true) {
                        viewModel.switchToProfile(named: profile.name)
                    }
                    .disabled(isProfileActionRunning)
                }

                simpleActionButton(
                    profile.connectionState == .needsLogin ? "Re-login" : "Login",
                    symbol: "person.crop.circle.badge.plus",
                    prominent: profile.connectionState == .needsLogin
                ) {
                    viewModel.openLoginInTerminal(for: profile.name)
                }
                .disabled(isProfileActionRunning)

                simpleActionButton("Status", symbol: "person.crop.circle.badge.checkmark") {
                    viewModel.checkLoginStatus(for: profile.name)
                }
                .disabled(isProfileActionRunning)

                Menu("More") {
                    Button("Import current auth") {
                        viewModel.importCurrentAuth(into: profile.name)
                    }
                }
                .disabled(isProfileActionRunning)
            }

            HStack(spacing: 8) {
                TextField("rename", text: renameBinding(for: profile.name))
                    .textFieldStyle(.roundedBorder)

                simpleActionButton("Rename", symbol: "pencil") {
                    viewModel.renameProfile(from: profile.name, to: renameDrafts[profile.name] ?? profile.name)
                }
                .disabled(cannotRename(profile.name) || isProfileActionRunning)
            }

            if let hint = profile.connectionHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(statusColor(for: profile.connectionState))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Danger Zone", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)

                Text("These actions are permanent and cannot be undone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Remove profile", role: .destructive) {
                        viewModel.removeProfile(named: profile.name, deleteData: false)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Remove + delete data", role: .destructive) {
                        viewModel.removeProfile(named: profile.name, deleteData: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.red.opacity(0.24), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var runtimeCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runtime")
                    .font(.headline)

                TextField("/opt/homebrew/bin/codex", text: $codexPathDraft)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    simpleActionButton("Save", symbol: "checkmark", prominent: true) {
                        viewModel.updateCustomNodePath(codexPathDraft)
                    }
                    .disabled(normalized(codexPathDraft) == viewModel.customNodePath)

                    simpleActionButton("Choose", symbol: "folder") {
                        viewModel.chooseCustomNodePath()
                    }

                    simpleActionButton("Use Auto", symbol: "sparkles") {
                        codexPathDraft = ""
                        viewModel.clearCustomNodePath()
                    }
                    .disabled(viewModel.customNodePath.isEmpty)
                }

                if let probe = viewModel.runtimeProbeSummary {
                    Text(probe)
                        .font(.caption2)
                        .foregroundStyle(viewModel.isCodexRuntimeAvailable ? Color.secondary : Color.orange)
                        .lineLimit(2)
                }

                Text("Leave empty to auto-detect codex from known paths or PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preferencesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Display")
                    .font(.headline)

                HStack {
                    Text("Reset labels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    simpleActionButton(viewModel.resetDisplayMode.buttonLabel, symbol: "clock") {
                        viewModel.toggleResetDisplayMode()
                    }
                }
            }
        }
    }

    private var diagnosticsCard: some View {
        SettingsCard {
            DisclosureGroup(isExpanded: $isDiagnosticsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if let hint = viewModel.cliResolutionHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                    } else {
                        Text("Run refresh to capture command resolution details.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    simpleActionButton("Open multicodex config directory", symbol: "folder.fill") {
                        viewModel.openMulticodexConfigDirectory()
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Troubleshooting & Diagnostics", systemImage: "wrench.and.screwdriver")
                    .font(.headline)
            }
        }
    }

    private var testSetupCard: some View {
        SettingsCard {
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
                        simpleActionButton("Reset Sandbox", symbol: "arrow.clockwise") {
                            viewModel.resetTemporaryAuthSandbox()
                        }
                        .disabled(isProfileActionRunning)

                        simpleActionButton("Open Folder", symbol: "folder") {
                            viewModel.openTemporaryAuthSandboxDirectory()
                        }

                        simpleActionButton("Use Real Config", symbol: "xmark.circle") {
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

    private func syncRenameDrafts() {
        let names = Set(viewModel.profiles.map(\.name))
        renameDrafts = renameDrafts.filter { names.contains($0.key) }
        for profile in viewModel.profiles where renameDrafts[profile.name] == nil {
            renameDrafts[profile.name] = profile.name
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private func simpleActionButton(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        ActionPillButton(title: title, symbol: symbol, prominent: prominent, action: action)
    }
}

private struct SettingsCard<Content: View>: View {
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
