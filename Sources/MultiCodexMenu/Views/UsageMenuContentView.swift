import AppKit
import SwiftUI

struct UsageMenuContentView: View {
    @ObservedObject var viewModel: UsageMenuViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedProfileName: String?
    @State private var keyboardMonitor: Any?
    @State private var expandedProfileNames: Set<String> = []

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                header

                if let alert = viewModel.prioritizedMenuAlert {
                    alertBanner(alert)
                }

                if viewModel.prioritizedMenuAlert == nil, let warning = viewModel.refreshWarningMessage {
                    subtleWarningRow(warning)
                }

                if viewModel.profiles.isEmpty {
                    emptyStateCard
                } else {
                    if let current = viewModel.currentProfile {
                        currentProfileCard(current)
                    }
                    quickProfilesCard
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
        .onChange(of: viewModel.profiles.map(\.name)) { _ in
            let activeNames = Set(viewModel.profiles.map(\.name))
            expandedProfileNames = expandedProfileNames.intersection(activeNames)
            synchronizeSelection()
        }
        .onChange(of: viewModel.focusedProfileName) { _ in
            synchronizeSelection()
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.profiles.map(\.name))
        .animation(.easeInOut(duration: 0.18), value: viewModel.switchingProfileName)
        .animation(.easeInOut(duration: 0.18), value: viewModel.profileActionInFlightName)
        .animation(.easeInOut(duration: 0.18), value: expandedProfileNames)
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

            ActionPillButton(
                title: "Refresh",
                symbol: "arrow.clockwise",
                role: .secondary,
                layout: .iconOnly,
                isDisabled: viewModel.isRefreshing
            ) {
                viewModel.refreshLive()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .help("Refresh usage (Cmd+R)")
        }
    }

    private func alertBanner(_ alert: MenuAlertState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: alertSymbol(for: alert.severity))
                .font(.caption.weight(.semibold))
                .foregroundStyle(alertColor(for: alert.severity))

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(alertColor(for: alert.severity))
                Text(alert.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            ActionPillButton(
                title: alert.actionTitle,
                symbol: "arrow.right.circle.fill",
                role: .primary,
                isDisabled: isActionBusy
            ) {
                performAlertAction(alert)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(alertColor(for: alert.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(alertColor(for: alert.severity).opacity(0.24), lineWidth: 1)
        )
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func currentProfileCard(_ profile: ProfileUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Profile")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                statePill(profile.connectionState.label, tone: statusColor(for: profile.connectionState))
            }

            HStack(spacing: 8) {
                CompactUsageMetric(
                    title: "5h",
                    metric: profile.usage.fiveHour,
                    resetDisplayMode: viewModel.resetDisplayMode,
                    progressValue: viewModel.progressValue(for: profile.usage.fiveHour)
                )
                CompactUsageMetric(
                    title: "weekly",
                    metric: profile.usage.weekly,
                    resetDisplayMode: viewModel.resetDisplayMode,
                    progressValue: viewModel.progressValue(for: profile.usage.weekly)
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }

    private var quickProfilesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Profiles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if hiddenProfilesCount > 0 {
                    Text("+\(hiddenProfilesCount) more in Settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 7) {
                ForEach(visibleRows) { row in
                    MenuProfileQuickRow(
                        row: row,
                        isSelected: row.name == selectedProfileName,
                        isExpanded: expandedProfileNames.contains(row.name),
                        fiveHourProgressValue: viewModel.progressValue(for: row.profile.usage.fiveHour),
                        weeklyProgressValue: viewModel.progressValue(for: row.profile.usage.weekly),
                        isBusy: isActionBusy,
                        isSwitching: viewModel.switchingProfileName == row.name,
                        isAuthRunning: viewModel.profileActionInFlightName == row.name,
                        onSelect: { selectedProfileName = row.name },
                        onPrimaryAction: { performPrimaryAction(for: row) },
                        onToggleExpanded: { toggleExpanded(row.name) }
                    )
                }
            }

            Text("Shortcuts: Cmd+R refresh, Cmd+, settings, ↑/↓ select, Enter action")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Set up your first profile", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))

            Text(onboardingCopy)
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

            HStack(spacing: 8) {
                ActionPillButton(
                    title: viewModel.isCodexRuntimeAvailable ? "Login First Profile" : "Fix Runtime",
                    symbol: viewModel.isCodexRuntimeAvailable ? "person.crop.circle.badge.plus" : "terminal",
                    role: .primary,
                    isDisabled: isActionBusy
                ) {
                    if viewModel.isCodexRuntimeAvailable {
                        viewModel.startNewProfileLogin()
                    } else {
                        viewModel.selectSettingsSection(.runtime)
                        openSettingsWindow()
                    }
                }

                ActionPillButton(title: "Settings", symbol: "gearshape.fill") {
                    openSettingsWindow()
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ActionPillButton(
                title: "Login New",
                symbol: "person.crop.circle.badge.plus",
                role: loginNewFooterRole,
                isDisabled: isActionBusy
            ) {
                viewModel.startNewProfileLogin()
            }

            Spacer()

            ActionPillButton(title: "Open Settings", symbol: "gearshape.fill") {
                openSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: [.command])
            .help("Open Settings (Cmd+,)")
        }
    }

    private var visibleRows: [ProfileRowState] {
        viewModel.menuProfileRows(limit: viewModel.preferredMenuProfileCount)
    }

    private var hiddenProfilesCount: Int {
        max(0, viewModel.profiles.count - visibleRows.count)
    }

    private var loginNewFooterRole: ActionPillRole {
        if viewModel.prioritizedMenuAlert != nil || viewModel.profiles.isEmpty {
            return .secondary
        }
        return .primary
    }

    private var onboardingCopy: String {
        switch viewModel.onboardingState.step {
        case .runtime:
            return "Confirm the codex runtime first, then connect your first profile."
        case .login:
            return "Login once and MultiCodex will start showing usage cards automatically."
        case .verify:
            return "Verify authentication status for your profile to finish setup."
        case .done:
            return "Your setup is complete."
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

    private func performAlertAction(_ alert: MenuAlertState) {
        switch alert.action {
        case .openRuntimeSettings:
            viewModel.selectSettingsSection(.runtime)
            openSettingsWindow()
        default:
            viewModel.performMenuAlertAction(alert.action)
        }
    }

    private func performPrimaryAction(for row: ProfileRowState) {
        switch row.primaryAction {
        case .switchProfile:
            viewModel.switchToProfile(named: row.name)
        case .relogin:
            viewModel.openLoginInTerminal(for: row.name)
        case .none:
            toggleExpanded(row.name)
        }
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

    private func statePill(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tone.opacity(0.14), in: Capsule())
            .foregroundStyle(tone)
    }

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func synchronizeSelection() {
        let names = visibleRows.map(\.name)

        if let focus = viewModel.focusedProfileName, names.contains(focus) {
            selectedProfileName = focus
            viewModel.dismissFocusHint()
            return
        }

        if let selectedProfileName, names.contains(selectedProfileName) {
            return
        }

        selectedProfileName = names.first
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
        if modifiers == [.command], event.charactersIgnoringModifiers == "," {
            openSettingsWindow()
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
        let names = visibleRows.map(\.name)
        guard !names.isEmpty else { return }

        guard let selectedProfileName,
              let idx = names.firstIndex(of: selectedProfileName)
        else {
            self.selectedProfileName = names.first
            return
        }

        let next = (idx + delta + names.count) % names.count
        self.selectedProfileName = names[next]
    }

    private func triggerPrimaryActionForSelection() {
        guard
            let selectedProfileName,
            let row = visibleRows.first(where: { $0.name == selectedProfileName })
        else {
            return
        }

        performPrimaryAction(for: row)
    }

    private func toggleExpanded(_ profileName: String) {
        if expandedProfileNames.contains(profileName) {
            expandedProfileNames.remove(profileName)
        } else {
            expandedProfileNames.insert(profileName)
        }
    }
}

private struct CompactUsageMetric: View {
    let title: String
    let metric: UsageMetric
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

private struct MenuProfileQuickRow: View {
    let row: ProfileRowState
    let isSelected: Bool
    let isExpanded: Bool
    let fiveHourProgressValue: Double
    let weeklyProgressValue: Double
    let isBusy: Bool
    let isSwitching: Bool
    let isAuthRunning: Bool
    let onSelect: () -> Void
    let onPrimaryAction: () -> Void
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if row.isCurrent {
                            statePill("Current", tone: .accentColor)
                        }
                        statePill(row.connectionState.label, tone: statusColor(for: row.connectionState))
                    }

                    HStack(spacing: 8) {
                        Text("5h \(row.fiveHourPercent)")
                        Text("weekly \(row.weeklyPercent)")
                        Text(row.resetText)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if row.primaryAction != .none {
                    if row.primaryAction == .switchProfile, isSwitching {
                        ProgressView()
                            .controlSize(.small)
                    } else if row.primaryAction == .relogin, isAuthRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        ActionPillButton(
                            title: row.primaryAction.title,
                            symbol: row.primaryAction.symbol,
                            role: .secondary,
                            isDisabled: isBusy,
                            action: onPrimaryAction
                        )
                    }
                }

                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide remaining limit" : "Show remaining limit")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        CompactUsageMetric(
                            title: "5h",
                            metric: row.profile.usage.fiveHour,
                            resetDisplayMode: row.resetDisplayMode,
                            progressValue: fiveHourProgressValue
                        )
                        CompactUsageMetric(
                            title: "weekly",
                            metric: row.profile.usage.weekly,
                            resetDisplayMode: row.resetDisplayMode,
                            progressValue: weeklyProgressValue
                        )
                    }

                    if let hint = row.profile.connectionHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(statusColor(for: row.connectionState))
                            .lineLimit(2)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(isSelected ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.48) : Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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

    private func statePill(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tone.opacity(0.14), in: Capsule())
            .foregroundStyle(tone)
    }
}
