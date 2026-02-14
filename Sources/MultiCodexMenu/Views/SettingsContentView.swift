import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var viewModel: UsageMenuViewModel
    @State private var codexPathDraft = ""
    @State private var renameDrafts: [String: String] = [:]

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headerCard
                    profilesCard
                    runtimeCard
                    preferencesCard
#if DEBUG
                    testSetupCard
#endif
                    diagnosticsCard
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

                Text("Manage profiles, login flow, runtime path, and usage preferences.")
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

    private var profilesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Profiles & Login")
                    .font(.headline)

                simpleActionButton("Login New Profile", symbol: "person.crop.circle.badge.plus", prominent: true) {
                    viewModel.startNewProfileLogin()
                }
                .disabled(isProfileActionRunning)

                Text("Start browser login, then rename the created profile if needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = viewModel.profileActionMessage {
                    feedbackRow(message, color: .green)
                }

                if let error = viewModel.profileActionError {
                    feedbackRow(error, color: .red)
                }

                if viewModel.profiles.isEmpty {
                    Text("No profiles configured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
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

    private func profileRow(_ profile: ProfileUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))

                if profile.isCurrent {
                    pill("Current", color: .accentColor)
                }
                if !profile.hasAuth {
                    pill("No auth", color: .orange)
                }

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

                simpleActionButton(profile.hasAuth ? "Login" : "Re-login", symbol: "person.crop.circle.badge.plus", prominent: !profile.hasAuth) {
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

                    Divider()

                    Button("Remove profile", role: .destructive) {
                        viewModel.removeProfile(named: profile.name, deleteData: false)
                    }

                    Button("Remove + delete data", role: .destructive) {
                        viewModel.removeProfile(named: profile.name, deleteData: true)
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

            if let status = profile.lastLoginStatusPreview {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var runtimeCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Codex Runtime")
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

                Text("Leave empty to auto-detect codex from standard install paths or PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Set this only if codex is not found. You can use a full path or command name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preferencesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Preferences")
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Diagnostics")
                    .font(.headline)

                if let hint = viewModel.cliResolutionHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else {
                    Text("Run a refresh to see command resolution details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                simpleActionButton("Open multicodex config directory", symbol: "folder.fill") {
                    viewModel.openMulticodexConfigDirectory()
                }
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
