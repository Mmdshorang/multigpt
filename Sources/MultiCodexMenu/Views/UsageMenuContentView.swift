import AppKit
import SwiftUI

struct UsageMenuContentView: View {
    @ObservedObject var viewModel: UsageMenuViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var expandedProfileNames: Set<String> = []
    @State private var selectedProfileName: String?
    @State private var keyboardMonitor: Any?
    private let maxVisibleProfiles = 6

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                header

                if viewModel.isUsingTemporaryAuthSandbox {
                    sandboxBanner
                }

                attentionQueue

                if viewModel.profiles.isEmpty {
                    onboardingCard
                } else {
                    if let current = viewModel.currentProfile {
                        currentStrip(profile: current)
                    }
                    profilesList
                }

                footer
            }
            .padding(12)

            if let toast = activeToast {
                toastView(text: toast.text, color: toast.color)
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            synchronizeSelection()
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: viewModel.profiles.map(\.name)) { names in
            expandedProfileNames = expandedProfileNames.filter { names.contains($0) }
            synchronizeSelection()
        }
        .onChange(of: viewModel.focusedProfileName) { _ in
            synchronizeSelection()
        }
        .animation(.easeInOut(duration: 0.18), value: expandedProfileNames)
        .animation(.easeInOut(duration: 0.18), value: viewModel.profiles.map(\.name))
        .animation(.easeInOut(duration: 0.18), value: viewModel.switchingProfileName)
        .animation(.easeInOut(duration: 0.18), value: viewModel.currentProfile?.name)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MultiCodex")
                    .font(.headline)

                Text(viewModel.lastUpdatedLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ActionPillButton(title: "Refresh", symbol: "arrow.clockwise", prominent: true, isDisabled: viewModel.isRefreshing) {
                viewModel.refreshLive()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refresh usage (Cmd+R)")
        }
    }

    @ViewBuilder
    private var attentionQueue: some View {
        if let error = viewModel.lastRefreshError {
            attentionRow(
                title: "Error",
                detail: error,
                color: .red,
                actionTitle: "Refresh Live",
                action: { viewModel.refreshLive() }
            )
        }

        if let authTarget = profilesNeedingLogin.first {
            let count = profilesNeedingLogin.count
            attentionRow(
                title: count == 1 ? "Needs Login" : "\(count) Need Login",
                detail: count == 1
                    ? "\(authTarget.name) needs authentication."
                    : "Multiple profiles need authentication.",
                color: .orange,
                actionTitle: "Re-login \(authTarget.name)",
                action: { viewModel.openLoginInTerminal(for: authTarget.name) }
            )
        }
    }

    private func attentionRow(
        title: String,
        detail: String,
        color: Color,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            ActionPillButton(title: actionTitle, symbol: "arrow.right.circle.fill", prominent: true, isDisabled: isActionBusy, action: action)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
    }

    private func currentStrip(profile: ProfileUsage) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Profile")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            UsageValueChip(title: "5h", value: profile.usage.fiveHour.percentText)
            UsageValueChip(title: "weekly", value: profile.usage.weekly.percentText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var profilesList: some View {
        VStack(spacing: 8) {
            ForEach(visibleProfiles) { profile in
                ProfileUsageCardView(
                    profile: profile,
                    resetDisplayMode: viewModel.resetDisplayMode,
                    isSwitching: viewModel.switchingProfileName == profile.name,
                    isRunningAuthAction: viewModel.profileActionInFlightName == profile.name,
                    isExpanded: expandedProfileNames.contains(profile.name),
                    isSelected: selectedProfileName == profile.name,
                    onSwitch: { viewModel.switchToProfile(named: profile.name) },
                    onRelogin: { viewModel.openLoginInTerminal(for: profile.name) },
                    onToggleExpanded: { toggleExpanded(profile.name) }
                )
                .onTapGesture {
                    selectedProfileName = profile.name
                }
            }

            if hiddenProfilesCount > 0 {
                Text("+\(hiddenProfilesCount) more profiles in Settings")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }

            Text("Shortcuts: Cmd+R refresh, ↑/↓ select, Enter action")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Set up your first profile", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))

            Text("Login once and MultiCodex will start showing usage cards automatically.")
                .font(.caption)
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

            ActionPillButton(title: "Login First Profile", symbol: "person.crop.circle.badge.plus", prominent: true, isDisabled: isActionBusy) {
                viewModel.startNewProfileLogin()
            }

            Button("Open Settings") {
                openSettingsWindow()
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ActionPillButton(title: "Login New", symbol: "person.crop.circle.badge.plus", prominent: true, isDisabled: isActionBusy) {
                viewModel.startNewProfileLogin()
            }

            Spacer()

            ActionPillButton(title: "Settings", symbol: "gearshape.fill") {
                openSettingsWindow()
            }
        }
    }

    private var sandboxBanner: some View {
        Label("Temporary auth sandbox active", systemImage: "testtube.2")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var activeToast: (text: String, color: Color)? {
        if let error = viewModel.profileActionError {
            return (error, .red)
        }
        if let message = viewModel.profileActionMessage {
            return (message, .green)
        }
        return nil
    }

    private func toastView(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(color.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
    }

    private var isActionBusy: Bool {
        viewModel.isRefreshing || viewModel.profileActionInFlightName != nil || viewModel.switchingProfileName != nil
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

    private var profilesNeedingLogin: [ProfileUsage] {
        viewModel.profiles.filter { $0.connectionState == .needsLogin }
    }

    private var visibleProfiles: [ProfileUsage] {
        Array(viewModel.profiles.prefix(maxVisibleProfiles))
    }

    private var hiddenProfilesCount: Int {
        max(0, viewModel.profiles.count - visibleProfiles.count)
    }

    private func toggleExpanded(_ profileName: String) {
        if expandedProfileNames.contains(profileName) {
            expandedProfileNames.remove(profileName)
        } else {
            expandedProfileNames.insert(profileName)
        }
        selectedProfileName = profileName
    }

    private func synchronizeSelection() {
        if let focus = viewModel.focusedProfileName, visibleProfiles.contains(where: { $0.name == focus }) {
            selectedProfileName = focus
            expandedProfileNames.insert(focus)
            viewModel.dismissFocusHint()
            return
        }

        if let selectedProfileName, visibleProfiles.contains(where: { $0.name == selectedProfileName }) {
            return
        }

        if let current = viewModel.currentProfile, visibleProfiles.contains(where: { $0.name == current.name }) {
            self.selectedProfileName = current.name
        } else {
            self.selectedProfileName = visibleProfiles.first?.name
        }
    }

    private func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "r" {
            viewModel.refreshLive()
            return true
        }

        switch event.keyCode {
        case 126: // up arrow
            moveSelection(-1)
            return true
        case 125: // down arrow
            moveSelection(1)
            return true
        case 36, 76: // return/enter
            triggerPrimaryActionForSelection()
            return true
        default:
            return false
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !visibleProfiles.isEmpty else { return }
        let names = visibleProfiles.map(\.name)
        guard let currentName = selectedProfileName, let idx = names.firstIndex(of: currentName) else {
            selectedProfileName = names.first
            return
        }

        let next = (idx + delta + names.count) % names.count
        selectedProfileName = names[next]
    }

    private func triggerPrimaryActionForSelection() {
        guard
            let selectedProfileName,
            let profile = visibleProfiles.first(where: { $0.name == selectedProfileName })
        else {
            return
        }

        if profile.connectionState == .needsLogin {
            viewModel.openLoginInTerminal(for: profile.name)
            return
        }

        if !profile.isCurrent {
            viewModel.switchToProfile(named: profile.name)
            return
        }

        toggleExpanded(profile.name)
    }
}

private struct UsageValueChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}
