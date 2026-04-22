import SwiftUI

extension SettingsContentView {
    var accountsPage: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(18)) {
            settingsHero(
                title: "Accounts",
                description: "Manage identities, keep usage readable, and make switching or recovery feel simple even when you are juggling several accounts.",
                symbol: "person.2.fill"
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    settingsBadge(
                        text: "\(viewModel.accounts.count) Configured",
                        symbol: "person.2.fill",
                        color: DashboardTokens.accent
                    )
                    settingsBadge(
                        text: viewModel.accountsNeedingLogin.isEmpty ? "No Recovery Needed" : "\(viewModel.accountsNeedingLogin.count) Need Login",
                        symbol: viewModel.accountsNeedingLogin.isEmpty ? "checkmark.circle.fill" : "person.crop.circle.badge.exclamationmark",
                        color: viewModel.accountsNeedingLogin.isEmpty ? DashboardTokens.statusGreen : DashboardTokens.statusOrange
                    )
                }
            }

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
                    HStack(alignment: .top, spacing: DashboardTokens.scaled(16)) {
                        settingsSectionIntro(
                            title: "Add Accounts",
                            description: "Start a new login instantly or queue a short batch when you are preparing fresh accounts.",
                            symbol: "person.crop.circle.badge.plus"
                        )

                        Spacer(minLength: DashboardTokens.scaled(12))

                        ActionPillButton(
                            title: "Login New Account",
                            symbol: "person.crop.circle.badge.plus",
                            role: .primary,
                            isDisabled: isAccountActionRunning
                        ) {
                            viewModel.startNewAccountLogin()
                        }
                    }

                    settingsInsetPanel(
                        title: "BATCH LOGIN",
                        description: "Create and log in multiple new accounts sequentially. Keep the batch modest so the flow stays predictable and easy to monitor."
                    ) {
                        HStack(spacing: 10) {
                            SettingsTextField(
                                placeholder: "Count",
                                text: sequentialLoginCountTextBinding
                            )
                            .frame(width: DashboardTokens.scaled(86))

                            ActionPillButton(
                                title: "Start Batch Login",
                                symbol: "list.number",
                                role: .secondary,
                                isDisabled: isAccountActionRunning
                            ) {
                                openSequentialLoginTracker()
                            }

                            Spacer(minLength: 0)
                        }
                    }

                    if let message = viewModel.accountActionMessage {
                        feedbackRow(message, color: DashboardTokens.statusGreen)
                    }

                    if let error = viewModel.accountActionError {
                        feedbackRow(error, color: DashboardTokens.statusRed)
                    }
                }
            }

            if viewModel.accounts.isEmpty && viewModel.isRefreshing {
                SettingsPanelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        settingsSectionIntro(
                            title: "Loading accounts",
                            description: "Fetching account and usage details from the runtime.",
                            symbol: "arrow.clockwise"
                        )

                        ProgressView()
                            .tint(DashboardTokens.accent)

                        settingsInfoRow(
                            symbol: "clock",
                            text: "This usually completes quickly after startup or a live refresh.",
                            color: DashboardTokens.textTertiary
                        )
                    }
                }
            } else if viewModel.accounts.isEmpty {
                SettingsPanelCard {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsSectionIntro(
                            title: "No Accounts Yet",
                            description: "Log in your first Codex account to unlock usage tracking, switching, and automation.",
                            symbol: "person.2.slash"
                        )

                        settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)

                        HStack(spacing: 10) {
                            ActionPillButton(
                                title: viewModel.isCodexRuntimeAvailable ? "Log In First Account" : "Open Runtime Settings",
                                symbol: viewModel.isCodexRuntimeAvailable ? "person.crop.circle.badge.plus" : "terminal",
                                role: .primary,
                                isDisabled: isAccountActionRunning
                            ) {
                                if viewModel.isCodexRuntimeAvailable {
                                    viewModel.startNewAccountLogin()
                                } else {
                                    viewModel.selectSettingsSection(.system)
                                }
                            }

                            if !viewModel.isCodexRuntimeAvailable {
                                ActionPillButton(title: "Refresh Runtime", symbol: "arrow.clockwise") {
                                    viewModel.refreshLive()
                                }
                            }
                        }
                    }
                }
            } else {
                SettingsPanelCard {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsSectionIntro(
                            title: "Organize the List",
                            description: "Find what you need quickly and keep sort rules aligned with how you actually choose accounts.",
                            symbol: "line.3.horizontal.decrease.circle"
                        )

                        HStack(alignment: .top, spacing: DashboardTokens.scaled(12)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Search")
                                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                                    .foregroundStyle(DashboardTokens.textPrimary)

                                SettingsTextField(
                                    placeholder: "Filter accounts",
                                    text: accountSearchBinding
                                )
                                .frame(maxWidth: DashboardTokens.scaled(280))
                            }

                            Spacer(minLength: 0)

                            settingsBadge(
                                text: "\(viewModel.filteredAccounts.count) Visible",
                                symbol: "eye",
                                color: DashboardTokens.accent
                            )
                        }

                        HStack(alignment: .top, spacing: 12) {
                            sortOptionColumn(title: "Sort by") {
                                SettingsSegmentedPicker(
                                    options: AccountSortCriterion.allCases,
                                    titleForOption: { $0.title },
                                    selection: accountSortCriterionBinding
                                )
                            }
                            .frame(minWidth: DashboardTokens.scaled(270), maxWidth: .infinity, alignment: .leading)

                            if viewModel.accountSortCriterion != .name {
                                sortOptionColumn(title: "Window") {
                                    SettingsSegmentedPicker(
                                        options: AccountSortWindow.allCases,
                                        titleForOption: { $0.title },
                                        selection: accountSortWindowBinding
                                    )
                                }
                                .frame(minWidth: DashboardTokens.scaled(170), maxWidth: DashboardTokens.scaled(190), alignment: .leading)
                            }

                            sortOptionColumn(title: "Direction") {
                                SettingsSegmentedPicker(
                                    options: SortDirection.allCases,
                                    titleForOption: { $0.shortTitle },
                                    selection: accountSortDirectionBinding
                                )
                            }
                            .frame(minWidth: DashboardTokens.scaled(170), maxWidth: DashboardTokens.scaled(190), alignment: .leading)
                        }

                        settingsInfoRow(
                            symbol: "info.circle",
                            text: "Current account pinning stays intact in the menu bar, while settings sorting includes every account so maintenance work remains predictable. Accounts without usage data are still pushed to the bottom.",
                            color: DashboardTokens.textTertiary
                        )
                    }
                }

                if viewModel.filteredAccounts.isEmpty {
                    SettingsPanelCard {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsSectionIntro(
                                title: "No Matching Accounts",
                                description: "Nothing matches your current search. Clear the filter or try a shorter query.",
                                symbol: "magnifyingglass"
                            )

                            ActionPillButton(
                                title: "Clear Filter",
                                symbol: "xmark.circle",
                                role: .secondary
                            ) {
                                viewModel.setAccountSearchQuery("")
                            }
                        }
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredAccounts) { account in
                            expandableAccountRow(account)
                        }
                    }
                }
            }
        }
    }

    func sortOptionColumn<Control: View>(
        title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(DashboardTokens.textSecondary)

            control()
        }
    }

    func expandableAccountRow(_ account: AccountUsage) -> some View {
        let isExpanded = expandedAccountNames.contains(account.name)
        let statusColor = AccountPresentation.statusColor(for: account.connectionState)
        let fiveHourText = viewModel.displayPercentText(for: account.usage.fiveHour)
        let weeklyText = viewModel.displayPercentText(for: account.usage.weekly)

        return SettingsPanelCard(
            fill: account.isCurrent ? DashboardTokens.accentBackground.opacity(0.5) : DashboardTokens.cardBackgroundElevated
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(DashboardTokens.Motion.emphasis(reduceMotion: reduceMotion)) {
                        toggleExpanded(account.name)
                    }
                } label: {
                    HStack(spacing: DashboardTokens.scaled(14)) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: DashboardTokens.scaled(10), height: DashboardTokens.scaled(10))

                        VStack(alignment: .leading, spacing: DashboardTokens.scaled(5)) {
                            HStack(spacing: DashboardTokens.scaled(8)) {
                                Text(account.name)
                                    .font(DashboardTokens.Font.accountName())
                                    .foregroundStyle(DashboardTokens.textPrimary)

                                if account.isCurrent {
                                    AccountStatusPill(text: "Active", color: DashboardTokens.accent)
                                } else if account.connectionState != .connected {
                                    AccountStatusPill(text: account.connectionState.label, color: statusColor)
                                }
                            }

                            Text(account.workspaceEmailHint ?? account.connectionState.label)
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: DashboardTokens.scaled(12))

                        VStack(alignment: .trailing, spacing: DashboardTokens.scaled(5)) {
                            Text("5h \(fiveHourText) • Week \(weeklyText)")
                                .font(DashboardTokens.Font.metadata().weight(.semibold))
                                .foregroundStyle(DashboardTokens.textPrimary)
                                .monospacedDigit()

                            Text(account.usage.fiveHour.resetText(mode: viewModel.resetDisplayMode))
                                .font(.system(size: DashboardTokens.scaled(11), weight: .regular))
                                .foregroundStyle(DashboardTokens.textTertiary)
                                .lineLimit(1)
                        }

                        Image(systemName: "chevron.down")
                            .font(.system(size: DashboardTokens.scaled(11), weight: .semibold))
                            .foregroundStyle(DashboardTokens.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: DashboardTokens.scaled(14), height: DashboardTokens.scaled(14))
                            .animation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion), value: isExpanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    expandedAccountContent(account)
                        .padding(.top, DashboardTokens.scaled(16))
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                            )
                        )
                }
            }
        }
    }

    func expandedAccountContent(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(16)) {
            Rectangle()
                .fill(DashboardTokens.cardBorder)
                .frame(height: 1)

            HStack(spacing: 8) {
                if !account.isCurrent {
                    ActionPillButton(
                        title: "Switch to Account",
                        symbol: "checkmark.circle.fill",
                        role: .primary
                    ) {
                        viewModel.switchToAccount(named: account.name)
                    }
                    .disabled(isAccountActionRunning)
                }

                ActionPillButton(
                    title: account.connectionState == .needsLogin ? "Re-Login" : "Open Login",
                    symbol: "person.crop.circle.badge.plus"
                ) {
                    viewModel.openLoginInTerminal(for: account.name)
                }
                .disabled(isAccountActionRunning)

                ActionPillButton(
                    title: "Check Status",
                    symbol: "person.crop.circle.badge.checkmark"
                ) {
                    viewModel.checkLoginStatus(for: account.name)
                }
                .disabled(isAccountActionRunning)
            }

            if account.usage.fiveHour.usedPercent != nil || account.usage.weekly.usedPercent != nil {
                settingsInsetPanel(title: "USAGE", description: "Quickly compare short-window pressure against weekly headroom before switching or retiring this account.") {
                    HStack(spacing: DashboardTokens.scaled(12)) {
                        AccountUsageMetricCard(
                            title: "5h",
                            metric: account.usage.fiveHour,
                            resetDisplayMode: viewModel.resetDisplayMode,
                            progressValue: viewModel.progressValue(for: account.usage.fiveHour),
                            valueText: viewModel.displayPercentText(for: account.usage.fiveHour)
                        )

                        AccountUsageMetricCard(
                            title: "Weekly",
                            metric: account.usage.weekly,
                            resetDisplayMode: viewModel.resetDisplayMode,
                            progressValue: viewModel.progressValue(for: account.usage.weekly),
                            valueText: viewModel.displayPercentText(for: account.usage.weekly)
                        )
                    }
                }
            }

            settingsInsetPanel(title: "RENAME", description: "Use a stable, human-readable name so switching remains obvious in the menu bar.") {
                HStack(spacing: 10) {
                    SettingsTextField(
                        placeholder: "New name",
                        text: renameBinding(for: account.name)
                    )

                    ActionPillButton(title: "Rename", symbol: "pencil", role: .secondary) {
                        viewModel.renameAccount(from: account.name, to: renameDrafts[account.name] ?? account.name)
                    }
                    .disabled(cannotRename(account.name) || isAccountActionRunning)
                }
            }

            settingsInsetPanel(title: "REMOVE", description: "Only remove accounts you no longer need. You can optionally delete local data at the same time.") {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        label: "Delete local account data on removal",
                        isOn: removeStoredDataBinding(for: account.name)
                    )

                    SettingsDestructiveButton(
                        title: removeStoredDataBinding(for: account.name).wrappedValue
                            ? "Remove and Delete Data"
                            : "Remove from MultiCodex",
                        isDisabled: isAccountActionRunning
                    ) {
                        viewModel.removeAccount(
                            named: account.name,
                            deleteData: removeStoredDataBinding(for: account.name).wrappedValue
                        )
                        removalDeleteDataChoice[account.name] = false
                    }
                }
            }
        }
    }

    func toggleExpanded(_ accountName: String) {
        if expandedAccountNames.contains(accountName) {
            expandedAccountNames.remove(accountName)
        } else {
            expandedAccountNames.insert(accountName)
        }
    }

    func syncExpandedAccounts() {
        let names = Set(viewModel.accounts.map(\.name))
        expandedAccountNames = expandedAccountNames.intersection(names)
    }

    private var sequentialLoginCountTextBinding: Binding<String> {
        Binding(
            get: { sequentialLoginCountText },
            set: { newValue in
                let digitsOnly = newValue.filter(\.isNumber)
                guard !digitsOnly.isEmpty else {
                    sequentialLoginCountText = ""
                    return
                }
                let parsed = Int(digitsOnly) ?? 1
                let clamped = max(1, min(SequentialLoginState.maxAccountCount, parsed))
                sequentialLoginCountText = String(clamped)
            }
        )
    }

    private func openSequentialLoginTracker() {
        let count = max(
            1,
            min(
                SequentialLoginState.maxAccountCount,
                Int(sequentialLoginCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
            )
        )
        sequentialLoginCountText = String(count)
        viewModel.prepareSequentialNewAccountLogin(count: count)
        openWindow(id: "batch-login")
    }
}
