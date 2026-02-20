import SwiftUI

extension SettingsContentView {
    var headerCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.title3.weight(.semibold))

                Text("Manage accounts, runtime setup, display preferences, and troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = viewModel.refreshWarningMessage {
                    SubtleWarningRow(text: warning)
                }

                HStack(spacing: 8) {
                    ActionPillButton(
                        title: "Refresh",
                        symbol: "arrow.clockwise",
                        role: .secondary,
                        layout: .iconOnly
                    ) {
                        viewModel.refresh()
                    }

                    ActionPillButton(title: "Refresh Live", symbol: "bolt.horizontal.fill", role: .secondary) {
                        viewModel.refreshLive()
                    }
                }
            }
        }
    }

    var dashboardPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dashboard")
                        .font(.headline)

                    HStack(spacing: 12) {
                        dashboardMetric(title: "Accounts", value: "\(viewModel.accounts.count)")
                        dashboardMetric(title: "Needs Login", value: "\(viewModel.accountsNeedingLogin.count)")
                        dashboardMetric(title: "Current", value: viewModel.currentAccount?.name ?? "-")
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
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func dashboardAlert(_ alert: MenuAlertState) -> some View {
        AlertActionCard(alert: alert) {
            handleAlertAction(alert)
        }
    }

    var onboardingWizardCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("First-Run Setup")
                    .font(.headline)

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
        HStack(spacing: 8) {
            Image(systemName: stepSymbol(step, isActive: isActive))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

            Text(step.title)
                .font(.caption)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)

            Spacer()
        }
    }

    var accountsPage: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Accounts")
                        .font(.headline)

                    Spacer()

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
                    HStack(spacing: 0) {
                        accountListPane
                            .frame(width: 260)

                        Divider()
                            .padding(.horizontal, 12)

                        accountDetailPane
                    }
                    .frame(minHeight: 380)
                }
            }
        }
    }

    var noAccountsState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No accounts yet", systemImage: "person.crop.circle.badge.plus")
                .font(.caption.weight(.semibold))

            Text("Use \"Login New Account\" to connect your first account.")
                .font(.caption2)
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
        }
    }

    var accountListPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search accounts", text: accountSearchBinding)
                .textFieldStyle(.roundedBorder)

            if viewModel.filteredAccounts.isEmpty {
                Text("No accounts match your search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.filteredAccounts) { account in
                            Button {
                                viewModel.selectSettingsAccount(named: account.name)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.name)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(account.connectionState.label)
                                            .font(.caption2)
                                            .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))
                                    }

                                    Spacer()

                                    if account.isCurrent {
                                        AccountStatusPill(text: "Current", color: .accentColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelectedAccount(account.name) ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isSelectedAccount(account.name) ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.10), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var accountDetailPane: some View {
        if let account = viewModel.selectedSettingsAccount {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    accountIdentitySection(account)
                    accountAuthSection(account)
                    accountUsageSection(account)
                    accountDangerSection(account)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select an account")
                    .font(.headline)
                Text("Choose an account from the left to manage it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func accountIdentitySection(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Identity")

            Text(account.name)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Rename account", text: renameBinding(for: account.name))
                    .textFieldStyle(.roundedBorder)

                ActionPillButton(title: "Rename", symbol: "pencil") {
                    viewModel.renameAccount(from: account.name, to: renameDrafts[account.name] ?? account.name)
                }
                .disabled(cannotRename(account.name) || isAccountActionRunning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func accountAuthSection(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Authentication")

            HStack(spacing: 8) {
                if !account.isCurrent {
                    ActionPillButton(title: "Use", symbol: "checkmark.circle.fill", role: .secondary) {
                        viewModel.switchToAccount(named: account.name)
                    }
                    .disabled(isAccountActionRunning)
                }

                ActionPillButton(
                    title: account.connectionState == .needsLogin ? "Re-login" : "Login",
                    symbol: "person.crop.circle.badge.plus",
                    role: .secondary
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
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

}
