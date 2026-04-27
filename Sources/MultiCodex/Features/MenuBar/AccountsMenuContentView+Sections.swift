import AppKit
import SwiftUI

// MARK: - Header

extension AccountsMenuContentView {
    var header: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.currentAccount?.name ?? "MultiCodex")
                    .font(DashboardTokens.Font.cardHeading())
                    .foregroundStyle(DashboardTokens.textPrimary)

                Text(headerSummaryText)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
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

                ActionPillButton(
                    title: "Settings",
                    symbol: "gearshape.fill",
                    role: .secondary,
                    layout: .iconOnly
                ) {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: [.command])
                .help("Open Settings (Cmd+,)")
            }
        }
        .cardStyle(fill: DashboardTokens.cardBackgroundSubtle)
    }
}

// MARK: - Sort Menus

extension AccountsMenuContentView {
    private var sortCriterionMenu: some View {
        Menu {
            Button { viewModel.setAccountSortCriterion(.used) } label: {
                menuSelectionLabel("Used", isSelected: viewModel.accountSortCriterion == .used)
            }
            Button { viewModel.setAccountSortCriterion(.remaining) } label: {
                menuSelectionLabel("Remaining", isSelected: viewModel.accountSortCriterion == .remaining)
            }
            Button { viewModel.setAccountSortCriterion(.name) } label: {
                menuSelectionLabel("Name", isSelected: viewModel.accountSortCriterion == .name)
            }
        } label: {
            sortOptionPill(value: viewModel.accountSortCriterion.title)
        }
        .menuStyle(.borderlessButton)
        .help("Sort criterion")
    }

    private var sortWindowMenu: some View {
        Menu {
            Button { viewModel.setAccountSortWindow(.fiveHour) } label: {
                menuSelectionLabel("5h", isSelected: viewModel.accountSortWindow == .fiveHour)
            }
            Button { viewModel.setAccountSortWindow(.weekly) } label: {
                menuSelectionLabel("Weekly", isSelected: viewModel.accountSortWindow == .weekly)
            }
        } label: {
            sortOptionPill(value: viewModel.accountSortWindow.title)
        }
        .menuStyle(.borderlessButton)
        .help("Sort window")
    }

    private var sortDirectionMenu: some View {
        Menu {
            Button { viewModel.setAccountSortDirection(.ascending) } label: {
                menuSelectionLabel("Low to high", isSelected: viewModel.accountSortDirection == .ascending)
            }
            Button { viewModel.setAccountSortDirection(.descending) } label: {
                menuSelectionLabel("High to low", isSelected: viewModel.accountSortDirection == .descending)
            }
        } label: {
            sortOptionPill(value: viewModel.accountSortDirection.shortTitle)
        }
        .menuStyle(.borderlessButton)
        .help("Sort direction")
    }

    private var sortOptionsRow: some View {
        HStack(spacing: 6) {
            sortCriterionMenu

            if viewModel.accountSortCriterion != .name {
                sortWindowMenu
            }

            sortDirectionMenu

            Spacer(minLength: 0)
        }
    }

    private func sortOptionPill(value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .foregroundColor(DashboardTokens.textPrimary)
                .fontWeight(.semibold)
        }
        .font(DashboardTokens.Font.metadata())
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(DashboardTokens.cardBackgroundSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }

    private func menuSelectionLabel(_ title: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(DashboardTokens.Font.microLabel())
            }
        }
    }
}

// MARK: - Alert Banner

extension AccountsMenuContentView {
    func alertBanner(_ alert: MenuAlertState) -> some View {
        AlertActionCard(
            alert: alert,
            isDisabled: isActionBusy
        ) {
            performAlertAction(alert)
        }
    }
}

// MARK: - Usage Section (Bento)

extension AccountsMenuContentView {
    var bentoUsageSection: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.Spacing.cardGap) {
            if let current = viewModel.currentAccount {
                HStack(spacing: DashboardTokens.Spacing.cardGap) {
                    usageCard(
                        title: viewModel.usageBarStyle == .depleting ? "5h Remaining" : "5h Usage",
                        progress: viewModel.progressValue(for: current.usage.fiveHour),
                        color: DashboardTokens.ringFiveHour,
                        ringLabel: "5H",
                        valueText: viewModel.displayPercentText(for: current.usage.fiveHour),
                        resetText: current.usage.fiveHour.resetText(mode: viewModel.resetDisplayMode)
                    )

                    usageCard(
                        title: viewModel.usageBarStyle == .depleting ? "Weekly Remaining" : "Weekly Usage",
                        progress: viewModel.progressValue(for: current.usage.weekly),
                        color: DashboardTokens.ringWeekly,
                        ringLabel: "WK",
                        valueText: viewModel.displayPercentText(for: current.usage.weekly),
                        resetText: current.usage.weekly.resetText(mode: viewModel.resetDisplayMode)
                    )
                }

                currentAccountCard(current)
            }
        }
    }

    private func usageCard(
        title: String,
        progress: Double,
        color: Color,
        ringLabel: String,
        valueText: String,
        resetText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DashboardSectionHeader(title: title)

            HStack(spacing: 10) {
                DashboardProgressRing(
                    progress: progress,
                    color: color,
                    label: ringLabel,
                    valueText: valueText,
                    size: 52,
                    expandHorizontally: false
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(valueText)
                        .font(DashboardTokens.Font.cardHeading())
                        .foregroundStyle(DashboardTokens.textPrimary)
                        .monospacedDigit()
                    Text(resetText)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(fill: DashboardTokens.cardBackgroundElevated)
    }

    private func currentAccountCard(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AccountPresentation.statusColor(for: account.connectionState).opacity(0.14))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: account.connectionState == .connected ? "person.crop.circle.fill" : "person.crop.circle.badge.exclamationmark")
                            .font(DashboardTokens.Font.bodySemibold())
                            .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(account.name)
                            .font(DashboardTokens.Font.accountName())
                            .foregroundStyle(DashboardTokens.textPrimary)
                            .lineLimit(1)
                    }

                    if let email = account.workspaceEmailHint {
                        Text(email)
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
        }
        .cardStyle(fill: DashboardTokens.cardBackgroundElevated)
    }
}

// MARK: - Runtime Status Panel

extension AccountsMenuContentView {
    private var runtimeStatusPanel: some View {
        HStack(spacing: 8) {
            Image(systemName: runtimeStatus.symbol)
                .font(DashboardTokens.Font.metadataBold())
                .foregroundStyle(runtimeStatus.color)

            Text(runtimeStatus.text)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(runtimeStatus.color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(runtimeStatus.color.opacity(0.14), lineWidth: 1)
        )
    }
}

// MARK: - Accounts Section

extension AccountsMenuContentView {
    var accountsSection: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.Spacing.cardGap) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    DashboardSectionHeader(title: "Accounts")
                    Text(accountsSummaryText)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                }

                Spacer()

                ActionPillButton(
                    title: areAllAccountsExpanded ? "Collapse All" : "Expand All",
                    symbol: areAllAccountsExpanded ? "chevron.up" : "chevron.down",
                    role: .secondary,
                    layout: .iconOnly
                ) {
                    toggleAllAccountsExpanded()
                }
                .help(areAllAccountsExpanded ? "Collapse all" : "Expand all")
            }

            healthSummaryRow

            sortOptionsRow

            VStack(spacing: 5) {
                ForEach(visibleRows) { row in
                    DashboardAccountRow(
                        row: row,
                        isExpanded: expandedAccountNames.contains(row.name),
                        fiveHourProgressValue: viewModel.progressValue(for: row.account.usage.fiveHour),
                        weeklyProgressValue: viewModel.progressValue(for: row.account.usage.weekly),
                        fiveHourPercentText: viewModel.displayPercentText(for: row.account.usage.fiveHour),
                        weeklyPercentText: viewModel.displayPercentText(for: row.account.usage.weekly),
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
        .cardStyle(fill: DashboardTokens.cardBackgroundElevated)
    }
}

// MARK: - Empty State

extension AccountsMenuContentView {
    var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((viewModel.isCodexRuntimeAvailable ? DashboardTokens.accent : DashboardTokens.statusOrange).opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: viewModel.isCodexRuntimeAvailable ? "person.crop.circle.badge.plus" : "exclamationmark.triangle")
                            .font(DashboardTokens.Font.headline())
                            .foregroundStyle(viewModel.isCodexRuntimeAvailable ? DashboardTokens.accent : DashboardTokens.statusOrange)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    DashboardSectionHeader(title: "Getting Started")
                    Text(viewModel.isCodexRuntimeAvailable ? "Add your first account" : "Finish runtime setup")
                        .font(DashboardTokens.Font.detailTitle())
                        .foregroundStyle(DashboardTokens.textPrimary)
                }
            }

            Text(onboardingCopy)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            runtimeStatusPanel

            HStack(spacing: DashboardTokens.Spacing.footerSpacing) {
                ActionPillButton(
                    title: viewModel.isCodexRuntimeAvailable ? "Log In First Account" : "Open Runtime Settings",
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

                if !viewModel.isCodexRuntimeAvailable {
                    ActionPillButton(title: "Refresh Runtime", symbol: "arrow.clockwise") {
                        viewModel.refreshLive()
                    }
                }
            }
        }
        .cardStyle(fill: DashboardTokens.cardBackgroundElevated)
    }
}

// MARK: - Loading State

extension AccountsMenuContentView {
    var loadingStateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DashboardTokens.accentBackground)
                    .frame(width: 30, height: 30)
                    .overlay(
                        ProgressView()
                            .controlSize(.small)
                            .tint(DashboardTokens.accent)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    DashboardSectionHeader(title: "Loading")
                    Text("Refreshing accounts and usage")
                        .font(DashboardTokens.Font.cardHeading())
                        .foregroundStyle(DashboardTokens.textPrimary)
                }
            }

            Text("Gathering runtime and account state. This usually takes a moment.")
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                loadingBar(width: 0.88, height: 8)
                loadingBar(width: 0.72, height: 8)
                loadingBar(width: 0.56, height: 8)
            }
            .accessibilityHidden(true)
        }
        .cardStyle(fill: DashboardTokens.cardBackgroundElevated)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading account data")
        .accessibilityValue("Refreshing accounts and usage")
    }

    private func loadingBar(width: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DashboardTokens.cardBorder)
                .frame(width: geometry.size.width * width, height: height)
        }
        .frame(height: height)
    }
}

// MARK: - Footer

extension AccountsMenuContentView {
    var footer: some View {
        HStack(spacing: DashboardTokens.Spacing.footerSpacing) {
            ActionPillButton(
                title: viewModel.accounts.isEmpty ? "Start Login" : "Login New",
                symbol: "person.crop.circle.badge.plus",
                role: loginNewFooterRole,
                isDisabled: isActionBusy
            ) {
                viewModel.startNewAccountLogin()
            }

            Spacer()

            if hiddenAccountsCount > 0, !viewModel.showAllAccountsInMenu {
                Text("+\(hiddenAccountsCount) hidden")
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textTertiary)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Computed Values

extension AccountsMenuContentView {
    var visibleRows: [AccountRowState] {
        if viewModel.showAllAccountsInMenu {
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

    var loginNewFooterRole: ActionPillRole {
        if viewModel.prioritizedMenuAlert != nil || viewModel.accounts.isEmpty {
            return .primary
        }
        return .secondary
    }

    var onboardingCopy: String {
        switch viewModel.onboardingState.step {
        case .runtime:
            return "Confirm that the Codex runtime is available first. Once healthy, connect your first account and MultiCodex will handle the rest."
        case .login:
            return "Log in once and MultiCodex will immediately start showing usage, headroom, and switching guidance."
        case .verify:
            return "Run a quick status check to verify authentication and finish the setup flow."
        case .done:
            return "Your setup is complete."
        }
    }

    var headerSummaryText: String {
        if viewModel.accounts.isEmpty {
            return "No accounts configured yet"
        }

        let healthyCount = viewModel.accounts.count - viewModel.accountsNeedingLogin.count
        return "\(healthyCount) ready \u{2022} \(viewModel.lastUpdatedLabel)"
    }

    var accountsSummaryText: String {
        if hiddenAccountsCount > 0, !viewModel.showAllAccountsInMenu {
            return "Showing \(visibleRows.count) of \(allRows.count)"
        }
        return "\(allRows.count) accounts"
    }

    private var healthSummaryRow: some View {
        let health = AccountsHealthSummary.from(viewModel.accounts)
        guard viewModel.accounts.count > 1 else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 8) {
                Text(health.summaryText)
                    .font(DashboardTokens.Font.caption())
                    .foregroundStyle(DashboardTokens.textSecondary)

                if health.atRiskAccounts > 0 {
                    Text("\(health.atRiskAccounts) at risk")
                        .font(DashboardTokens.Font.caption())
                        .foregroundStyle(DashboardTokens.statusOrange)
                }

                Spacer()

                if let nextReset = health.nextResetAt {
                    Text("Next reset: \(UsageFormatter.resetText(for: nextReset, mode: .relative))")
                        .font(DashboardTokens.Font.caption())
                        .foregroundStyle(DashboardTokens.textTertiary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DashboardTokens.cardBackgroundSubtle)
            )
        )
    }
}

// MARK: - Actions

extension AccountsMenuContentView {
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
            withAnimation(DashboardTokens.Motion.emphasis(reduceMotion: reduceMotion)) {
                toggleExpanded(row.name)
            }
        }
    }

    var activeToast: (text: String, color: Color)? {
        if let error = viewModel.accountActionError {
            return (error, DashboardTokens.statusRed)
        }
        if let message = viewModel.accountActionMessage {
            return (message, DashboardTokens.accentSoft)
        }
        return nil
    }

    func toastView(text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(text)
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(DashboardTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(DashboardTokens.cardBackgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(color.opacity(0.28), lineWidth: 1)
        )
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
        withAnimation(DashboardTokens.Motion.emphasis(reduceMotion: reduceMotion)) {
            if areAllAccountsExpanded {
                expandedAccountNames.subtract(visibleNames)
            } else {
                expandedAccountNames.formUnion(visibleNames)
            }
        }
    }

}
