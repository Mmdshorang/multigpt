import SwiftUI

// MARK: - Accounts Page
// Simplified single column with expandable rows

extension SettingsContentView {
    var accountsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Card
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        settingsSectionIntro(
                            title: "Accounts",
                            description: "Manage your coding agent accounts"
                        )

                        Spacer()

                        ActionPillButton(
                            title: "Login New",
                            symbol: "person.crop.circle.badge.plus",
                            role: .primary,
                            isDisabled: isAccountActionRunning
                        ) {
                            viewModel.startNewAccountLogin()
                        }
                    }

                    if let message = viewModel.accountActionMessage {
                        feedbackRow(message, color: .green)
                    }

                    if let error = viewModel.accountActionError {
                        feedbackRow(error, color: .red)
                    }
                }
            }

            // Account List
            if viewModel.accounts.isEmpty {
                SettingsPanelCard {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 24))
                                .foregroundStyle(DashboardTokens.textSecondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("No accounts yet")
                                    .font(DashboardTokens.Font.cardHeading())
                                    .foregroundStyle(DashboardTokens.textPrimary)

                                Text("Log in your first account to get started")
                                    .font(DashboardTokens.Font.metadata())
                                    .foregroundStyle(DashboardTokens.textSecondary)
                            }
                        }

                        settingsInfoRow(symbol: runtimeStatus.symbol, text: runtimeStatus.text, color: runtimeStatus.color)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.accounts) { account in
                        expandableAccountRow(account)
                    }
                }
            }
        }
    }

    func expandableAccountRow(_ account: AccountUsage) -> some View {
        let isExpanded = expandedAccountNames.contains(account.name)

        return SettingsPanelCard(padding: 12) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row (always visible)
                Button {
                    toggleExpanded(account.name)
                } label: {
                    HStack(spacing: 12) {
                        // Status dot
                        Circle()
                            .fill(AccountPresentation.statusColor(for: account.connectionState))
                            .frame(width: 8, height: 8)

                        // Account name
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DashboardTokens.textPrimary)

                            if let workspaceHint = account.workspaceEmailHint {
                                Text(workspaceHint)
                                    .font(DashboardTokens.Font.metadata())
                                    .foregroundStyle(DashboardTokens.textSecondary)
                            } else {
                                Text(account.connectionState.label)
                                    .font(DashboardTokens.Font.metadata())
                                    .foregroundStyle(AccountPresentation.statusColor(for: account.connectionState))
                            }
                        }

                        Spacer()

                        // Current badge
                        if account.isCurrent {
                            AccountStatusPill(text: "Active", color: DashboardTokens.accent)
                        }

                        // Expand chevron
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DashboardTokens.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded content
                if isExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.vertical, 4)

                        // Actions row
                        HStack(spacing: 8) {
                            if !account.isCurrent {
                                ActionPillButton(
                                    title: "Switch",
                                    symbol: "checkmark.circle.fill",
                                    role: .primary
                                ) {
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

                            ActionPillButton(
                                title: "Status",
                                symbol: "person.crop.circle.badge.checkmark"
                            ) {
                                viewModel.checkLoginStatus(for: account.name)
                            }
                            .disabled(isAccountActionRunning)
                        }

                        // Rename
                        HStack(spacing: 8) {
                            TextField("Rename account", text: renameBinding(for: account.name))
                                .textFieldStyle(.roundedBorder)

                            ActionPillButton(title: "Rename", symbol: "pencil") {
                                viewModel.renameAccount(from: account.name, to: renameDrafts[account.name] ?? account.name)
                            }
                            .disabled(cannotRename(account.name) || isAccountActionRunning)
                        }

                        // Usage
                        if account.usage.fiveHour.usedPercent != nil || account.usage.weekly.usedPercent != nil {
                            HStack(spacing: 12) {
                                usageMiniCard(
                                    title: "5h",
                                    metric: account.usage.fiveHour,
                                    progress: viewModel.progressValue(for: account.usage.fiveHour)
                                )

                                usageMiniCard(
                                    title: "Weekly",
                                    metric: account.usage.weekly,
                                    progress: viewModel.progressValue(for: account.usage.weekly)
                                )
                            }
                        }

                        // Danger zone
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Also delete local account data", isOn: removeStoredDataBinding(for: account.name))
                                .toggleStyle(.switch)
                                .font(.caption)

                            Button(
                                removeStoredDataBinding(for: account.name).wrappedValue ? "Remove and Delete Data" : "Remove from MultiCodex",
                                role: .destructive
                            ) {
                                viewModel.removeAccount(
                                    named: account.name,
                                    deleteData: removeStoredDataBinding(for: account.name).wrappedValue
                                )
                                removalDeleteDataChoice[account.name] = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isAccountActionRunning)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    func usageMiniCard(title: String, metric: UsageMetric, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DashboardTokens.Font.metadata())
                .foregroundStyle(DashboardTokens.textTertiary)

            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(DashboardTokens.accent)
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(width: 40, height: 4)

                Text(metric.percentText)
                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                    .foregroundStyle(DashboardTokens.textPrimary)
            }

                        Text(metric.resetText(mode: viewModel.resetDisplayMode))
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }

    func toggleExpanded(_ accountName: String) {
        if expandedAccountNames.contains(accountName) {
            expandedAccountNames.remove(accountName)
        } else {
            expandedAccountNames.insert(accountName)
        }
    }

    func syncExpandedAccounts() {
        // Remove expanded states for accounts that no longer exist
        let names = Set(viewModel.accounts.map(\.name))
        expandedAccountNames = expandedAccountNames.intersection(names)
    }
}
