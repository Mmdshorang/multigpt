import SwiftUI

extension SettingsContentView {
    var headerCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    settingsInfoRow(symbol: "person.2.fill", text: "\(viewModel.accounts.count) accounts")
                    settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        ActionPillButton(
                            title: "Refresh",
                            symbol: "arrow.clockwise",
                            role: .secondary,
                            layout: .iconOnly
                        ) {
                            viewModel.refresh()
                        }

                        ActionPillButton(title: "Refresh Live", symbol: "bolt.horizontal.fill", role: .primary) {
                            viewModel.refreshLive()
                        }
                    }
                }

                if let warning = viewModel.refreshWarningMessage {
                    SubtleWarningRow(text: warning)
                }
            }
        }
    }

    var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    settingsSectionIntro(
                        title: "Overview",
                        description: "Quick status for this install."
                    )

                    HStack(spacing: 8) {
                        dashboardMetric(title: "Current Account", value: viewModel.currentAccount?.name ?? "None")
                        dashboardMetric(title: "Needs Login", value: "\(viewModel.accountsNeedingLogin.count)")
                        dashboardMetric(title: "Setup", value: viewModel.onboardingState.step.title)
                    }

                    if let alert = viewModel.prioritizedMenuAlert {
                        dashboardAlert(alert)
                    }
                }
            }

            if !viewModel.onboardingState.isComplete {
                onboardingWizardCard
            }
        }
    }

    func dashboardMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    func dashboardAlert(_ alert: MenuAlertState) -> some View {
        AlertActionCard(alert: alert) {
            handleAlertAction(alert)
        }
    }

    var onboardingWizardCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro(
                    title: "First-Run Setup",
                    description: "Finish the initial setup."
                )

                VStack(alignment: .leading, spacing: 6) {
                    onboardingStepRow(.runtime, isActive: viewModel.onboardingState.step == .runtime)
                    onboardingStepRow(.login, isActive: viewModel.onboardingState.step == .login)
                    onboardingStepRow(.verify, isActive: viewModel.onboardingState.step == .verify)
                    onboardingStepRow(.done, isActive: viewModel.onboardingState.step == .done)
                }

                HStack(spacing: 8) {
                    switch viewModel.onboardingState.step {
                    case .runtime:
                        ActionPillButton(title: "Open Runtime", symbol: "terminal", role: .primary) {
                            viewModel.selectSettingsSection(.runtime)
                        }
                    case .login:
                        ActionPillButton(title: "Login First Account", symbol: "person.crop.circle.badge.plus", role: .primary) {
                            viewModel.startNewAccountLogin()
                        }
                    case .verify:
                        ActionPillButton(title: "Check Status", symbol: "person.crop.circle.badge.checkmark", role: .primary) {
                            if let current = viewModel.currentAccount {
                                viewModel.checkLoginStatus(for: current.name)
                            } else {
                                viewModel.refreshLive()
                            }
                        }
                    case .done:
                        ActionPillButton(title: "Finish", symbol: "checkmark.circle.fill", role: .primary) {
                            viewModel.markOnboardingCompleted()
                        }
                    }

                    ActionPillButton(title: "Reset Wizard", symbol: "arrow.counterclockwise") {
                        viewModel.resetOnboardingProgress()
                    }
                }
            }
        }
    }

    func onboardingStepRow(_ step: OnboardingStep, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: stepSymbol(step, isActive: isActive))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            Text(step.title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            Spacer()
        }
        .padding(.vertical, 2)
    }

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
                .font(.caption.weight(.semibold))
                .foregroundStyle(strategy == viewModel.accountSwitchingStrategy ? Color.accentColor : Color.secondary)
                .frame(width: 14, alignment: .top)

            VStack(alignment: .leading, spacing: 2) {
                Text(strategy.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(strategy.descriptionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    var accountListPane: some View {
        settingsInsetPanel(title: "Saved Accounts") {
            TextField("Search accounts", text: accountSearchBinding)
                .textFieldStyle(.roundedBorder)

            if viewModel.filteredAccounts.isEmpty {
                Text("No accounts match your search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(account.connectionState.label)
                        .font(.caption2)
                        .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))

                    if account.connectionState != .connected, let hint = account.connectionHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if account.isCurrent {
                    AccountStatusPill(text: "Current", color: .accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelectedAccount(account.name) ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

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
                    AccountStatusPill(text: "Current", color: .accentColor)
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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(AccountPresentation.statusColor(for: account.connectionState).opacity(0.08))
                )
            }
        }
    }

}
