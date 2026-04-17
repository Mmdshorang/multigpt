import AppKit
import SwiftUI

extension AccountsMenuContentView {
    var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MULTICODEX")
                    .font(DashboardTokens.Font.sectionLabel())
                    .tracking(1.5)
                    .foregroundStyle(DashboardTokens.textTertiary)

                Text(viewModel.lastUpdatedLabel)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
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
            isDisabled: isActionBusy
        ) {
            performAlertAction(alert)
        }
    }

    var bentoUsageSection: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.Spacing.cardGap) {
            if let current = viewModel.currentAccount {
                HStack(spacing: DashboardTokens.Spacing.cardGap) {
                    VStack(alignment: .leading, spacing: 6) {
                        DashboardSectionHeader(title: "5h usage")
                        DashboardProgressRing(
                            progress: viewModel.progressValue(for: current.usage.fiveHour),
                            color: DashboardTokens.ringFiveHour,
                            label: "5H",
                            valueText: current.usage.fiveHour.percentText
                        )
                        Text(current.usage.fiveHour.resetText(mode: viewModel.resetDisplayMode))
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DashboardTokens.Spacing.cardPadding)
                    .background(
                        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                            .fill(DashboardTokens.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                            .stroke(DashboardTokens.cardBorder, lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        DashboardSectionHeader(title: "weekly usage")
                        DashboardProgressRing(
                            progress: viewModel.progressValue(for: current.usage.weekly),
                            color: DashboardTokens.ringWeekly,
                            label: "WEEK",
                            valueText: current.usage.weekly.percentText
                        )
                        Text(current.usage.weekly.resetText(mode: viewModel.resetDisplayMode))
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(DashboardTokens.Spacing.cardPadding)
                    .background(
                        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                            .fill(DashboardTokens.cardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                            .stroke(DashboardTokens.cardBorder, lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    DashboardSectionHeader(title: "current account")

                    HStack(spacing: 8) {
                        Circle()
                            .fill(AccountPresentation.statusColor(for: current.connectionState))
                            .frame(width: DashboardTokens.Spacing.dotSize, height: DashboardTokens.Spacing.dotSize)

                        Text(current.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DashboardTokens.textPrimary)
                            .lineLimit(1)

                        if current.connectionState != .connected {
                            AccountStatusPill(
                                text: current.connectionState.label,
                                color: AccountPresentation.statusColor(for: current.connectionState)
                            )
                        }

                        Spacer()
                    }
                }
                .padding(DashboardTokens.Spacing.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                        .fill(DashboardTokens.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                        .stroke(DashboardTokens.cardBorder, lineWidth: 1)
                )
            }
        }
    }

    var accountsSection: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.Spacing.cardGap) {
            HStack {
                DashboardSectionHeader(title: "accounts")
                Spacer()
                if hiddenAccountsCount > 0, !showAllAccounts {
                    Text("+\(hiddenAccountsCount) more")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                }
                if canToggleShowAll {
                    ActionPillButton(
                        title: showAllAccounts ? "Show Less" : "Show All",
                        symbol: showAllAccounts ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
                        role: .secondary
                    ) {
                        toggleShowAllAccounts()
                    }
                    .help(showAllAccounts ? "Show fewer accounts in the menu" : "Show all accounts in the menu")
                }
                ActionPillButton(
                    title: areAllAccountsExpanded ? "Collapse All" : "Expand All",
                    symbol: areAllAccountsExpanded ? "chevron.up" : "chevron.down",
                    role: .secondary,
                    layout: .iconOnly
                ) {
                    toggleAllAccountsExpanded()
                }
                .help(areAllAccountsExpanded ? "Collapse all accounts" : "Expand all accounts")
            }
            .padding(.horizontal, 4)

            VStack(spacing: 4) {
                ForEach(visibleRows) { row in
                    DashboardAccountRow(
                        row: row,
                        isExpanded: expandedAccountNames.contains(row.name),
                        fiveHourProgressValue: viewModel.progressValue(for: row.account.usage.fiveHour),
                        weeklyProgressValue: viewModel.progressValue(for: row.account.usage.weekly),
                        isBusy: isActionBusy,
                        isSwitching: viewModel.switchingAccountName == row.name,
                        isAuthRunning: viewModel.accountActionInFlightName == row.name,
                        onActivate: { performPrimaryAction(for: row) },
                        onRowTap: { toggleExpanded(row.name) },
                        onToggleExpanded: { toggleExpanded(row.name) }
                    )
                }
            }
        }
        .padding(DashboardTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill(DashboardTokens.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }

    var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.Spacing.sectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                DashboardSectionHeader(title: "getting started")

                Text("Set up your first account")
                    .font(DashboardTokens.Font.detailTitle())
                    .foregroundStyle(DashboardTokens.textPrimary)
            }

            Text(onboardingCopy)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: runtimeStatus.symbol)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(runtimeStatus.color)
                Text(runtimeStatus.text)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(viewModel.isCodexRuntimeAvailable ? DashboardTokens.textSecondary : runtimeStatus.color)
                    .lineLimit(2)
            }

            HStack(spacing: DashboardTokens.Spacing.footerSpacing) {
                ActionPillButton(
                    title: viewModel.isCodexRuntimeAvailable ? "Login First Account" : "Fix Runtime",
                    symbol: viewModel.isCodexRuntimeAvailable ? "person.crop.circle.badge.plus" : "terminal",
                    role: .primary,
                    isDisabled: isActionBusy
                ) {
                    if viewModel.isCodexRuntimeAvailable {
                        viewModel.startNewAccountLogin()
                    } else {
                        viewModel.selectSettingsSection(.system)
                        openSettingsWindow()
                    }
                }

                ActionPillButton(title: "Settings", symbol: "gearshape.fill") {
                    openSettingsWindow()
                }
            }
        }
        .padding(DashboardTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill(DashboardTokens.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }

    var footer: some View {
        HStack(spacing: DashboardTokens.Spacing.footerSpacing) {
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
        if showAllAccounts {
            return allRows
        }
        return Array(allRows.prefix(viewModel.preferredMenuAccountCount))
    }

    var allRows: [AccountRowState] {
        viewModel.menuListAccounts.map { account in
            AccountRowState(account: account, resetDisplayMode: viewModel.resetDisplayMode)
        }
    }

    var hiddenAccountsCount: Int {
        max(0, allRows.count - visibleRows.count)
    }

    var canToggleShowAll: Bool {
        allRows.count > viewModel.preferredMenuAccountCount
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
            viewModel.selectSettingsSection(.system)
            openSettingsWindow()
        default:
            viewModel.performMenuAlertAction(alert.action)
        }
    }

    func performPrimaryAction(for row: AccountRowState) {
        switch row.primaryAction {
        case .switchAccount:
            guard !isActionBusy else { return }
            viewModel.switchToAccount(named: row.name)
        case .relogin:
            guard !isActionBusy else { return }
            viewModel.openLoginInTerminal(for: row.name)
        case .none:
            toggleExpanded(row.name)
        }
    }

    var activeToast: (text: String, color: Color)? {
        if let error = viewModel.accountActionError {
            return (error, DashboardTokens.statusRed)
        }
        if let message = viewModel.accountActionMessage {
            return (message, DashboardTokens.statusGreen)
        }
        return nil
    }

    func toastView(text: String, color: Color) -> some View {
        Text(text)
            .font(DashboardTokens.Font.metadata().weight(.semibold))
            .foregroundStyle(DashboardTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                    .fill(DashboardTokens.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                    .stroke(color.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
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
        return false
    }

    func toggleExpanded(_ accountName: String) {
        if expandedAccountNames.contains(accountName) {
            expandedAccountNames.remove(accountName)
        } else {
            expandedAccountNames.insert(accountName)
        }
    }

    var areAllAccountsExpanded: Bool {
        let visibleNames = Set(visibleRows.map(\.name))
        guard !visibleNames.isEmpty else { return false }
        return visibleNames.isSubset(of: expandedAccountNames)
    }

    func toggleAllAccountsExpanded() {
        let visibleNames = Set(visibleRows.map(\.name))
        if areAllAccountsExpanded {
            expandedAccountNames.subtract(visibleNames)
        } else {
            expandedAccountNames.formUnion(visibleNames)
        }
    }

    func toggleShowAllAccounts() {
        showAllAccounts.toggle()
    }
}
