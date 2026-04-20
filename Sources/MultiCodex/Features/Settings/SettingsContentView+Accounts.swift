import SwiftUI

extension SettingsContentView {
    var accountsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        settingsSectionIntro(
                            title: "Accounts",
                            description: "Manage your coding agent accounts",
                            symbol: "person.2.fill"
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

            SettingsPanelCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingsSectionIntro(
                        title: "Sorting",
                        description: "Choose the account order used in the menu and settings lists",
                        symbol: "arrow.up.arrow.down"
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DashboardTokens.textTertiary)
                                        .frame(width: 16)

                                    Text("Accounts sorting")
                                        .font(DashboardTokens.Font.metadata().weight(.semibold))
                                        .foregroundStyle(DashboardTokens.textPrimary)
                                }

                                Text("Built for list-style controls")
                                    .font(DashboardTokens.Font.metadata())
                                    .foregroundStyle(DashboardTokens.textSecondary)
                            }

                            Spacer(minLength: 16)

                            HStack(alignment: .top, spacing: 10) {
                                sortOptionColumn(
                                    title: "Sort by",
                                    width: 260
                                ) {
                                    SettingsSegmentedPicker(
                                        options: AccountSortCriterion.allCases,
                                        titleForOption: { $0.title },
                                        selection: accountSortCriterionBinding
                                    )
                                }

                                if viewModel.accountSortCriterion != .name {
                                    sortOptionColumn(
                                        title: "Window",
                                        width: 180
                                    ) {
                                        SettingsSegmentedPicker(
                                            options: AccountSortWindow.allCases,
                                            titleForOption: { $0.title },
                                            selection: accountSortWindowBinding
                                        )
                                    }
                                }

                                sortOptionColumn(
                                    title: "Direction",
                                    width: 220
                                ) {
                                    SettingsSegmentedPicker(
                                        options: SortDirection.allCases,
                                        titleForOption: { $0.shortTitle },
                                        selection: accountSortDirectionBinding
                                    )
                                }
                            }
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(DashboardTokens.textTertiary)
                                .frame(width: 16)

                            Text("Current account stays pinned to the top, and accounts without usage data are pushed to the bottom.")
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

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

    func sortOptionColumn<Control: View>(
        title: String,
        width: CGFloat,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(DashboardTokens.textPrimary)

            control()
        }
        .frame(width: width, alignment: .leading)
    }

    func expandableAccountRow(_ account: AccountUsage) -> some View {
        let isExpanded = expandedAccountNames.contains(account.name)

        return SettingsPanelCard(padding: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggleExpanded(account.name)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(AccountPresentation.statusColor(for: account.connectionState))
                            .frame(width: 8, height: 8)

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

                        if account.isCurrent {
                            AccountStatusPill(text: "Active", color: DashboardTokens.accent)
                        }

                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 16) {
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.vertical, 4)

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

                        if account.usage.fiveHour.usedPercent != nil || account.usage.weekly.usedPercent != nil {
                            settingsInsetPanel(title: "USAGE") {
                                HStack(spacing: 8) {
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

                        settingsInsetPanel(title: "RENAME") {
                            HStack(spacing: 8) {
                                SettingsTextField(
                                    placeholder: "New name",
                                    text: renameBinding(for: account.name)
                                )

                                ActionPillButton(title: "Rename", symbol: "pencil") {
                                    viewModel.renameAccount(from: account.name, to: renameDrafts[account.name] ?? account.name)
                                }
                                .disabled(cannotRename(account.name) || isAccountActionRunning)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
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
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                                .fill(DashboardTokens.destructiveBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                                .stroke(DashboardTokens.destructiveBorder, lineWidth: 1)
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
}
