import SwiftUI

extension SettingsContentView {
    var headerCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        settingsSectionIntro(
                            eyebrow: "Workspace",
                            title: "A calmer control center for MultiCodex",
                            description: "Everything here is organized around the tasks people actually do: checking account health, fixing runtime setup, and adjusting everyday preferences."
                        )

                        HStack(spacing: 8) {
                            AccountStatusPill(text: runtimeStatus.text, color: runtimeStatus.color)

                            if viewModel.isRefreshing {
                                AccountStatusPill(text: "Refreshing", color: .accentColor)
                            }
                        }
                    }

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

                HStack(spacing: 12) {
                    settingsMetricTile(
                        title: "Accounts",
                        value: "\(viewModel.accounts.count)",
                        detail: viewModel.accounts.isEmpty ? "No accounts connected yet" : "\(viewModel.accountsNeedingLogin.count) need attention"
                    )
                    settingsMetricTile(
                        title: "Current",
                        value: viewModel.currentAccount?.name ?? "None",
                        detail: viewModel.currentAccount?.connectionState.label ?? "Select or add an account",
                        tint: .green
                    )
                    settingsMetricTile(
                        title: "Updated",
                        value: viewModel.lastUpdatedLabel.replacingOccurrences(of: "Updated ", with: ""),
                        detail: viewModel.runtimeProbeSummary ?? "Runtime status will appear here",
                        tint: runtimeStatus.color
                    )
                }

                if let warning = viewModel.refreshWarningMessage {
                    SubtleWarningRow(text: warning)
                }
            }
        }
    }

    var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        eyebrow: "Overview",
                        title: "System status at a glance",
                        description: "Use the dashboard to see account readiness, onboarding progress, and any issues that need quick action."
                    )

                    HStack(spacing: 12) {
                        settingsMetricTile(
                            title: "Needs Login",
                            value: "\(viewModel.accountsNeedingLogin.count)",
                            detail: viewModel.accountsNeedingLogin.isEmpty ? "All connected accounts look healthy" : "Accounts needing re-authentication",
                            tint: viewModel.accountsNeedingLogin.isEmpty ? .green : .orange
                        )
                        settingsMetricTile(
                            title: "Runtime",
                            value: viewModel.isCodexRuntimeAvailable ? "Ready" : "Check Required",
                            detail: runtimeStatus.text,
                            tint: runtimeStatus.color
                        )
                        settingsMetricTile(
                            title: "Setup",
                            value: viewModel.onboardingState.step.title,
                            detail: viewModel.onboardingState.isComplete ? "Initial setup is complete" : "Continue the guided first-run flow",
                            tint: viewModel.onboardingState.isComplete ? .green : .accentColor
                        )
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

    func dashboardAlert(_ alert: MenuAlertState) -> some View {
        AlertActionCard(alert: alert) {
            handleAlertAction(alert)
        }
    }

    var onboardingWizardCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionIntro(
                    eyebrow: "First Run",
                    title: "Finish the initial setup",
                    description: "The wizard keeps the basics in the right order so new accounts come online smoothly."
                )

                VStack(alignment: .leading, spacing: 8) {
                    onboardingStepRow(.runtime, isActive: viewModel.onboardingState.step == .runtime)
                    onboardingStepRow(.login, isActive: viewModel.onboardingState.step == .login)
                    onboardingStepRow(.verify, isActive: viewModel.onboardingState.step == .verify)
                    onboardingStepRow(.done, isActive: viewModel.onboardingState.step == .done)
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

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

            if isActive {
                Text("Current")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    var accountsPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    settingsSectionIntro(
                        eyebrow: "Accounts",
                        title: "Manage identities with less friction",
                        description: "Search, switch, repair, and clean up accounts from one place without losing context."
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

                if viewModel.accounts.isEmpty {
                    noAccountsState
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        accountListPane
                            .frame(width: 290)

                        accountDetailPane
                    }
                    .frame(minHeight: 420)
                }
            }
        }
    }

    var noAccountsState: some View {
        settingsInsetPanel(
            title: "No accounts connected",
            description: "Connect your first account to unlock switching, usage tracking, and live diagnostics.",
            tint: .accentColor
        ) {
            settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)

            Text("Use \"Login New Account\" once the runtime is ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var accountListPane: some View {
        settingsInsetPanel(
            title: "Account Directory",
            description: "Search across saved accounts and pick one to inspect in detail.",
            tint: .accentColor
        ) {
            TextField("Search accounts", text: accountSearchBinding)
                .textFieldStyle(.roundedBorder)

            Text("\(viewModel.filteredAccounts.count) visible")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if viewModel.filteredAccounts.isEmpty {
                Text("No accounts match your search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
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
                ZStack {
                    Circle()
                        .fill(AccountPresentation.statusColor(for: account.connectionState).opacity(0.15))
                        .frame(width: 30, height: 30)

                    Image(systemName: account.isCurrent ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(account.connectionState.label)
                        .font(.caption2)
                        .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if account.isCurrent {
                        AccountStatusPill(text: "Current", color: .accentColor)
                    }

                    Text(account.lastUsedLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelectedAccount(account.name) ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelectedAccount(account.name) ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var accountDetailPane: some View {
        if let account = viewModel.selectedSettingsAccount {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsInsetPanel(
                        title: account.name,
                        description: account.isCurrent ? "This account is currently active in MultiCodex." : "Review account state and switch to it when needed.",
                        tint: AccountPresentation.statusColor(for: account.connectionState)
                    ) {
                        HStack(spacing: 8) {
                            AccountStatusPill(text: account.connectionState.label, color: AccountPresentation.statusColor(for: account.connectionState))

                            if account.isCurrent {
                                AccountStatusPill(text: "Current", color: .accentColor)
                            }
                        }

                        settingsInfoRow(symbol: "clock", text: "Last used \(account.lastUsedLabel)")
                    }

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
                description: "Choose an account from the directory to manage its name, authentication, and stored data.",
                tint: .accentColor
            ) {
                settingsInfoRow(symbol: "sidebar.left", text: "The left column keeps the account list available while you work.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func accountIdentitySection(_ account: AccountUsage) -> some View {
        settingsInsetPanel(
            title: "Identity",
            description: "Keep account names recognizable so switching is fast and low-risk.",
            tint: .accentColor
        ) {
            settingsFormRow("Display name", detail: "Shown across the menu bar and settings views.") {
                TextField("Rename account", text: renameBinding(for: account.name))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
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
            description: "Use these actions when you need to switch, re-check login state, or import existing auth.",
            tint: AccountPresentation.statusColor(for: account.connectionState)
        ) {
            HStack(spacing: 8) {
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
        }
    }
}
