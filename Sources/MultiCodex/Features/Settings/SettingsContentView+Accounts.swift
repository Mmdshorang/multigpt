import SwiftUI

extension SettingsContentView {
    // MARK: - Accounts Page

    var accountsPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    settingsSectionIntro(
                        title: "Accounts",
                        description: "Manage saved accounts."
                    )

                    Spacer(minLength: 0)

                    ActionPillButton(title: "Login New Account", symbol: "person.crop.circle.badge.plus", role: .primary, isDisabled: isAccountActionRunning) {
                        viewModel.startNewAccountLogin()
                    }
                }

                if let message = viewModel.accountActionMessage {
                    feedbackRow(message, color: .green)
                }

                if let error = viewModel.accountActionError {
                    feedbackRow(error, color: .red)
                }

                accountSwitchingSection

                if viewModel.accounts.isEmpty {
                    noAccountsState
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        accountListPane
                            .frame(width: 200)

                        accountDetailPane
                    }
                    .frame(minHeight: 280)
                }
            }
        }
    }

    var noAccountsState: some View {
        settingsInsetPanel(
            title: "No accounts yet",
            description: "Connect your first account to start tracking usage and switching identities."
        ) {
            settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)
        }
    }

    var accountSwitchingSection: some View {
        settingsInsetPanel(
            title: "Switching Strategy",
            description: "Choose how MultiCodex should decide when to move between accounts."
        ) {
            settingsFormRow("Strategy", detail: viewModel.accountSwitchingStrategy.descriptionText) {
                Picker("Switching strategy", selection: accountSwitchingStrategyBinding) {
                    ForEach(AccountSwitchingStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(AccountSwitchingStrategy.allCases) { strategy in
                    switchingStrategyRow(strategy)
                }
            }

            settingsFormRow(
                "Auto-switch notifications",
                detail: "Optional silent notification when MultiCodex switches accounts for you."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show silent notifications", isOn: autoSwitchNotificationsBinding)
                        .toggleStyle(.switch)

                    ActionPillButton(
                        title: "Send Test Notification",
                        symbol: "bell.badge",
                        isDisabled: !viewModel.autoSwitchNotificationsEnabled
                    ) {
                        viewModel.sendTestAutoSwitchNotification()
                    }
                }
            }

            settingsInfoRow(
                symbol: "info.circle",
                text: "If Codex is already running, you may need to restart that session after login or account switching."
            )
        }
    }

    func switchingStrategyRow(_ strategy: AccountSwitchingStrategy) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: strategy == viewModel.accountSwitchingStrategy ? "checkmark.circle.fill" : "circle")
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(strategy == viewModel.accountSwitchingStrategy ? DashboardTokens.accent : DashboardTokens.textSecondary)
                .frame(width: 14, alignment: .top)

            VStack(alignment: .leading, spacing: 2) {
                Text(strategy.title)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)

                Text(strategy.descriptionText)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Account List Pane

    var accountListPane: some View {
        settingsInsetPanel(title: "Saved Accounts") {
            TextField("Search accounts", text: accountSearchBinding)
                .textFieldStyle(.roundedBorder)

            if viewModel.filteredAccounts.isEmpty {
                Text("No accounts match your search.")
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.filteredAccounts) { account in
                            accountListRow(account)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    func accountListRow(_ account: AccountUsage) -> some View {
        Button {
            viewModel.selectSettingsAccount(named: account.name)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name)
                        .font(DashboardTokens.Font.metadata().weight(.semibold))
                        .foregroundStyle(DashboardTokens.textPrimary)
                        .lineLimit(1)

                    Text(account.connectionState.label)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))

                    if account.connectionState != .connected, let hint = account.connectionHint {
                        Text(hint)
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if account.isCurrent {
                    AccountStatusPill(text: "Current", color: DashboardTokens.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                    .fill(isSelectedAccount(account.name) ? DashboardTokens.accentBackground : Color.white.opacity(0.02))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Account Detail Pane

    @ViewBuilder
    var accountDetailPane: some View {
        if let account = viewModel.selectedSettingsAccount {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    accountIdentitySection(account)
                    accountAuthSection(account)
                    accountUsageSection(account)
                    accountDangerSection(account)
                }
            }
            .scrollIndicators(.hidden)
        } else {
            settingsInsetPanel(
                title: "Select an account",
                description: "Choose an account from the list to manage it."
            ) {
                EmptyView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func accountIdentitySection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Identity",
            description: "Rename the account so it is easy to recognize."
        ) {
            settingsFormRow("Display name") {
                TextField("Rename account", text: renameBinding(for: account.name))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                AccountStatusPill(text: account.connectionState.label, color: AccountPresentation.statusColor(for: account.connectionState))

                if account.isCurrent {
                    AccountStatusPill(text: "Current", color: DashboardTokens.accent)
                }

                Spacer()

                ActionPillButton(title: "Rename", symbol: "pencil") {
                    viewModel.renameAccount(from: account.name, to: renameDrafts[account.name] ?? account.name)
                }
                .disabled(cannotRename(account.name) || isAccountActionRunning)
            }
        }
    }

    func accountAuthSection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Authentication",
            description: "Switch, log in again, or import auth for this account."
        ) {
            HStack(spacing: 6) {
                if !account.isCurrent {
                    ActionPillButton(title: "Use", symbol: "checkmark.circle.fill", role: .primary) {
                        viewModel.switchToAccount(named: account.name)
                    }
                    .disabled(isAccountActionRunning)
                }

                ActionPillButton(
                    title: account.connectionState == .needsLogin ? "Re-login" : "Login",
                    symbol: "person.crop.circle.badge.plus"
                ) {
                    viewModel.openLoginInTerminal(for: account.name)
                }
                .disabled(isAccountActionRunning)

                ActionPillButton(title: "Status", symbol: "person.crop.circle.badge.checkmark") {
                    viewModel.checkLoginStatus(for: account.name)
                }
                .disabled(isAccountActionRunning)

                ActionPillButton(title: "Import Auth", symbol: "square.and.arrow.down") {
                    viewModel.importCurrentAuth(into: account.name)
                }
                .disabled(isAccountActionRunning)
            }

            if let hint = account.connectionHint {
                settingsInfoRow(
                    symbol: "info.circle.fill",
                    text: hint,
                    color: AccountPresentation.statusColor(for: account.connectionState)
                )
            }

            if let detail = account.connectionDetail {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.connectionState == .error ? "Latest issue" : "Login status")
                        .font(DashboardTokens.Font.metadata().weight(.semibold))
                        .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))

                    Text(detail)
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(DashboardTokens.Spacing.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                        .fill(AccountPresentation.statusColor(for: account.connectionState).opacity(0.08))
                )
            }
        }
    }

    func accountUsageSection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Usage",
            description: "Current usage for this account."
        ) {
            HStack(spacing: 10) {
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

            settingsInfoRow(symbol: "clock", text: "Last used \(account.lastUsedLabel)")
        }
    }

    func accountDangerSection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Remove Account",
            description: "Remove this account from MultiCodex. You can also delete its saved local auth and metadata."
        ) {
            Toggle("Also delete local account data", isOn: removeStoredDataBinding(for: account.name))
                .toggleStyle(.switch)
                .font(.caption)

            settingsInfoRow(
                symbol: "info.circle",
                text: account.isCurrent
                    ? "If this is the current account, MultiCodex will switch to another saved account or disconnect cleanly."
                    : "This only affects MultiCodex on this Mac."
            )

            HStack(spacing: 8) {
                Button(removeStoredDataBinding(for: account.name).wrappedValue ? "Remove and Delete Data" : "Remove from MultiCodex", role: .destructive) {
                    viewModel.removeAccount(
                        named: account.name,
                        deleteData: removeStoredDataBinding(for: account.name).wrappedValue
                    )
                    removalDeleteDataChoice[account.name] = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isAccountActionRunning)

                Text(removeStoredDataBinding(for: account.name).wrappedValue ? "Local saved auth files will be deleted too." : "Saved local data stays on disk unless you opt in.")
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
