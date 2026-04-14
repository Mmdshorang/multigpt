import AppKit
import SwiftUI

extension AccountsMenuContentView {
    var safeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("MultiCodex")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    viewModel.refreshLive()
                }
                .disabled(viewModel.isRefreshing)
            }

            Text(viewModel.lastUpdatedLabel)
                .font(.caption)
        }
    }

    func safeAlertBanner(_ alert: MenuAlertState) -> some View {
        HStack {
            Text(alert.title)
                .font(.caption.weight(.semibold))
            Text(alert.message)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    var safeEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No accounts yet.")
                .font(.subheadline.weight(.semibold))
            Button("Login First Account") {
                viewModel.startNewAccountLogin()
            }
            Button("Open Settings") {
                openSettingsWindow()
            }
        }
        .padding(layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    var safeAccountsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let current = viewModel.currentAccount {
                Text("Current: \(current.name)")
                    .font(.caption.weight(.semibold))
            }

            ForEach(visibleRows) { row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.caption)
                        .lineLimit(1)

                    if row.isCurrent {
                        Text("Current")
                            .font(.caption2)
                    }

                    if row.connectionState != .connected {
                        Text(row.connectionState.label)
                            .font(.caption2)
                    }

                    Spacer()

                    switch row.primaryAction {
                    case .switchAccount:
                        Button("Switch") {
                            viewModel.switchToAccount(named: row.name)
                        }
                        .font(.caption)
                    case .relogin:
                        Button("Re-login") {
                            viewModel.openLoginInTerminal(for: row.name)
                        }
                        .font(.caption)
                    case .none:
                        EmptyView()
                    }
                }
            }
        }
        .padding(layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    var safeFooter: some View {
        HStack {
            Button("Login New") {
                viewModel.startNewAccountLogin()
            }
            Spacer()
            Button("Settings") {
                openSettingsWindow()
            }
        }
    }

    var header: some View {
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

    func alertBanner(_ alert: MenuAlertState) -> some View {
        AlertActionCard(
            alert: alert,
            isDisabled: isActionBusy,
            horizontalPadding: layout.cardPadding,
            verticalPadding: max(6, layout.cardPadding - 1),
            cornerRadius: layout.cardCornerRadius,
            fillOpacity: 0.07,
            borderOpacity: layout.cardBorderOpacity + 0.08
        ) {
            performAlertAction(alert)
        }
    }

    func currentAccountCard(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: max(6, layout.sectionSpacing - 2)) {
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
                if !DebugFeatureFlags.hideConnectedBadge || account.connectionState != .connected {
                    AccountStatusPill(
                        text: account.connectionState.label,
                        color: AccountPresentation.statusColor(for: account.connectionState)
                    )
                }
            }

            HStack(spacing: max(6, layout.sectionSpacing - 2)) {
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
        .padding(layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(layout.cardBorderOpacity), lineWidth: 1)
        )
    }

    var quickAccountsCard: some View {
        VStack(alignment: .leading, spacing: max(6, layout.sectionSpacing - 2)) {
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

            VStack(spacing: layout.rowListSpacing) {
                ForEach(visibleRows) { row in
                    MenuAccountQuickRow(
                        row: row,
                        layout: layout,
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
        }
        .padding(layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(layout.cardBorderOpacity), lineWidth: 1)
        )
    }

    var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: max(6, layout.sectionSpacing - 1)) {
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
        .padding(layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(layout.cardBorderOpacity), lineWidth: 1)
        )
    }

    var footer: some View {
        HStack(spacing: layout.footerSpacing) {
            ActionPillButton(
                title: "Login New",
                symbol: "person.crop.circle.badge.plus",
                role: loginNewFooterRole,
                isDisabled: isActionBusy
            ) {
                viewModel.startNewAccountLogin()
            }

            Spacer()

            ActionPillButton(
                title: "Open Settings",
                symbol: "gearshape.fill",
                layout: .iconOnly
            ) {
                openSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: [.command])
            .help("Open Settings (Cmd+,)")
        }
    }

    var visibleRows: [AccountRowState] {
        viewModel.menuAccountRows(limit: viewModel.preferredMenuAccountCount)
    }

    var hiddenAccountsCount: Int {
        max(0, viewModel.menuListAccounts.count - visibleRows.count)
    }

    var loginNewFooterRole: ActionPillRole {
        if viewModel.prioritizedMenuAlert != nil || viewModel.accounts.isEmpty {
            return .secondary
        }
        return .primary
    }

    var onboardingCopy: String {
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

    func performAlertAction(_ alert: MenuAlertState) {
        switch alert.action {
        case .openRuntimeSettings:
            viewModel.selectSettingsSection(.runtime)
            openSettingsWindow()
        default:
            viewModel.performMenuAlertAction(alert.action)
        }
    }

    func performPrimaryAction(for row: AccountRowState) {
        switch row.primaryAction {
        case .switchAccount:
            viewModel.switchToAccount(named: row.name)
        case .relogin:
            viewModel.openLoginInTerminal(for: row.name)
        case .none:
            toggleExpanded(row.name)
        }
    }

    var activeToast: (text: String, color: Color)? {
        if let error = viewModel.accountActionError {
            return (error, .red)
        }
        if let message = viewModel.accountActionMessage {
            return (message, .green)
        }
        return nil
    }

    func toastView(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, layout.toastHorizontalPadding)
            .padding(.vertical, layout.toastVerticalPadding)
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

    var isActionBusy: Bool {
        viewModel.isRefreshing || viewModel.accountActionInFlightName != nil || viewModel.switchingAccountName != nil
    }

    var runtimeStatus: RuntimeStatusPresentation {
        AccountPresentation.runtimeStatus(
            summary: viewModel.runtimeProbeSummary,
            isAvailable: viewModel.isCodexRuntimeAvailable
        )
    }

    func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    func synchronizeSelection() {
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

    func installKeyboardMonitor() {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
    }

    func handleKeyEvent(_ event: NSEvent) -> Bool {
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

    func moveSelection(_ delta: Int) {
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

    func triggerPrimaryActionForSelection() {
        guard
            let selectedAccountName,
            let row = visibleRows.first(where: { $0.name == selectedAccountName })
        else {
            return
        }

        performPrimaryAction(for: row)
    }

    func toggleExpanded(_ accountName: String) {
        if expandedAccountNames.contains(accountName) {
            expandedAccountNames.remove(accountName)
        } else {
            expandedAccountNames.insert(accountName)
        }
    }
}
