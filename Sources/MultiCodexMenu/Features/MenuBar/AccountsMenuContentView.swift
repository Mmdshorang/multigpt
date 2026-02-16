import AppKit
import SwiftUI

struct AccountsMenuContentView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedAccountName: String?
    @State private var keyboardMonitor: Any?
    @State private var expandedAccountNames: Set<String> = []

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
                    SubtleWarningRow(text: warning)
                }

                if viewModel.accounts.isEmpty {
                    emptyStateCard
                } else {
                    if let current = viewModel.currentAccount {
                        currentAccountCard(current)
                    }
                    quickAccountsCard
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
        .onChange(of: viewModel.accounts.map(\.name)) { _ in
            let activeNames = Set(viewModel.accounts.map(\.name))
            expandedAccountNames = expandedAccountNames.intersection(activeNames)
            synchronizeSelection()
        }
        .onChange(of: viewModel.focusedAccountName) { _ in
            synchronizeSelection()
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.accounts.map(\.name))
        .animation(.easeInOut(duration: 0.18), value: viewModel.switchingAccountName)
        .animation(.easeInOut(duration: 0.18), value: viewModel.accountActionInFlightName)
        .animation(.easeInOut(duration: 0.18), value: expandedAccountNames)
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
            Image(systemName: AccountPresentation.alertSymbol(for: alert.severity))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AccountPresentation.alertColor(for: alert.severity))

            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AccountPresentation.alertColor(for: alert.severity))
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
        .background(AccountPresentation.alertColor(for: alert.severity).opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AccountPresentation.alertColor(for: alert.severity).opacity(0.24), lineWidth: 1)
        )
    }

    private func currentAccountCard(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Account")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(account.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                AccountStatusPill(
                    text: account.connectionState.label,
                    color: AccountPresentation.statusColor(for: account.connectionState)
                )
            }

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

    private var quickAccountsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Accounts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if hiddenAccountsCount > 0 {
                    Text("+\(hiddenAccountsCount) more in Settings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 7) {
                ForEach(visibleRows) { row in
                    MenuAccountQuickRow(
                        row: row,
                        isSelected: row.name == selectedAccountName,
                        isExpanded: expandedAccountNames.contains(row.name),
                        fiveHourProgressValue: viewModel.progressValue(for: row.account.usage.fiveHour),
                        weeklyProgressValue: viewModel.progressValue(for: row.account.usage.weekly),
                        isBusy: isActionBusy,
                        isSwitching: viewModel.switchingAccountName == row.name,
                        isAuthRunning: viewModel.accountActionInFlightName == row.name,
                        onSelect: { selectedAccountName = row.name },
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
            Label("Set up your first account", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))

            Text(onboardingCopy)
                .font(.caption)
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

            HStack(spacing: 8) {
                ActionPillButton(
                    title: viewModel.isCodexRuntimeAvailable ? "Login First Account" : "Fix Runtime",
                    symbol: viewModel.isCodexRuntimeAvailable ? "person.crop.circle.badge.plus" : "terminal",
                    role: .primary,
                    isDisabled: isActionBusy
                ) {
                    if viewModel.isCodexRuntimeAvailable {
                        viewModel.startNewAccountLogin()
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
                viewModel.startNewAccountLogin()
            }

            Spacer()

            ActionPillButton(title: "Open Settings", symbol: "gearshape.fill") {
                openSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: [.command])
            .help("Open Settings (Cmd+,)")
        }
    }

    private var visibleRows: [AccountRowState] {
        viewModel.menuAccountRows(limit: viewModel.preferredMenuAccountCount)
    }

    private var hiddenAccountsCount: Int {
        max(0, viewModel.accounts.count - visibleRows.count)
    }

    private var loginNewFooterRole: ActionPillRole {
        if viewModel.prioritizedMenuAlert != nil || viewModel.accounts.isEmpty {
            return .secondary
        }
        return .primary
    }

    private var onboardingCopy: String {
        switch viewModel.onboardingState.step {
        case .runtime:
            return "Confirm the codex runtime first, then connect your first account."
        case .login:
            return "Login once and MultiCodex will start showing usage cards automatically."
        case .verify:
            return "Verify authentication status for your account to finish setup."
        case .done:
            return "Your setup is complete."
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

    private func performPrimaryAction(for row: AccountRowState) {
        switch row.primaryAction {
        case .switchAccount:
            viewModel.switchToAccount(named: row.name)
        case .relogin:
            viewModel.openLoginInTerminal(for: row.name)
        case .none:
            toggleExpanded(row.name)
        }
    }

    private var activeToast: (text: String, color: Color)? {
        if let error = viewModel.accountActionError {
            return (error, .red)
        }
        if let message = viewModel.accountActionMessage {
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
        viewModel.isRefreshing || viewModel.accountActionInFlightName != nil || viewModel.switchingAccountName != nil
    }

    private var runtimeStatus: RuntimeStatusPresentation {
        AccountPresentation.runtimeStatus(
            summary: viewModel.runtimeProbeSummary,
            isAvailable: viewModel.isCodexRuntimeAvailable
        )
    }

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func synchronizeSelection() {
        let names = visibleRows.map(\.name)

        if let focus = viewModel.focusedAccountName, names.contains(focus) {
            selectedAccountName = focus
            viewModel.dismissFocusHint()
            return
        }

        if let selectedAccountName, names.contains(selectedAccountName) {
            return
        }

        selectedAccountName = names.first
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

        guard let selectedAccountName,
              let idx = names.firstIndex(of: selectedAccountName)
        else {
            self.selectedAccountName = names.first
            return
        }

        let next = (idx + delta + names.count) % names.count
        self.selectedAccountName = names[next]
    }

    private func triggerPrimaryActionForSelection() {
        guard
            let selectedAccountName,
            let row = visibleRows.first(where: { $0.name == selectedAccountName })
        else {
            return
        }

        performPrimaryAction(for: row)
    }

    private func toggleExpanded(_ accountName: String) {
        if expandedAccountNames.contains(accountName) {
            expandedAccountNames.remove(accountName)
        } else {
            expandedAccountNames.insert(accountName)
        }
    }
}

private struct MenuAccountQuickRow: View {
    let row: AccountRowState
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
                            AccountStatusPill(text: "Current", color: .accentColor)
                        }
                        AccountStatusPill(
                            text: row.connectionState.label,
                            color: AccountPresentation.statusColor(for: row.connectionState)
                        )
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
                    if row.primaryAction == .switchAccount, isSwitching {
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
                        AccountUsageMetricCard(
                            title: "5h",
                            metric: row.account.usage.fiveHour,
                            resetDisplayMode: row.resetDisplayMode,
                            progressValue: fiveHourProgressValue
                        )
                        AccountUsageMetricCard(
                            title: "weekly",
                            metric: row.account.usage.weekly,
                            resetDisplayMode: row.resetDisplayMode,
                            progressValue: weeklyProgressValue
                        )
                    }

                    if let hint = row.account.connectionHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(AccountPresentation.statusColor(for: row.connectionState))
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

}
