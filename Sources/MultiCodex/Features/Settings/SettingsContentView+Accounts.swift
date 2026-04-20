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
                SettingsPanelCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DashboardTokens.textTertiary)
                                    .frame(width: 16)

                                Text("List options")
                                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                                    .foregroundStyle(DashboardTokens.textPrimary)
                            }

                            Spacer(minLength: 12)

                            SettingsTextField(
                                placeholder: "Filter accounts",
                                text: accountSearchBinding
                            )
                            .frame(width: 230)
                        }

                        HStack(alignment: .top, spacing: 10) {
                            sortOptionColumn(title: "Sort by") {
                                SettingsSegmentedPicker(
                                    options: AccountSortCriterion.allCases,
                                    titleForOption: { $0.title },
                                    selection: accountSortCriterionBinding
                                )
                            }
                            .frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)

                            if viewModel.accountSortCriterion != .name {
                                sortOptionColumn(title: "Window") {
                                    SettingsSegmentedPicker(
                                        options: AccountSortWindow.allCases,
                                        titleForOption: { $0.title },
                                        selection: accountSortWindowBinding
                                    )
                                }
                                .frame(minWidth: 150, maxWidth: 170, alignment: .leading)
                            }

                            sortOptionColumn(title: "Direction") {
                                SettingsSegmentedPicker(
                                    options: SortDirection.allCases,
                                    titleForOption: { $0.shortTitle },
                                    selection: accountSortDirectionBinding
                                )
                            }
                            .frame(minWidth: 160, maxWidth: 190, alignment: .leading)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(DashboardTokens.textTertiary)
                                .frame(width: 16)

                            Text("Accounts are sorted by the selected list options, and accounts without usage data are pushed to the bottom.")
                                .font(DashboardTokens.Font.metadata())
                                .foregroundStyle(DashboardTokens.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if viewModel.filteredAccounts.isEmpty {
                    SettingsPanelCard {
                        VStack(alignment: .leading, spacing: 10) {
                            settingsSectionIntro(
                                title: "No Matching Accounts",
                                description: "Try a different filter query to see matching accounts.",
                                symbol: "line.3.horizontal.decrease.circle"
                            )

                            HStack {
                                ActionPillButton(
                                    title: "Clear Filter",
                                    symbol: "xmark.circle",
                                    role: .secondary
                                ) {
                                    viewModel.setAccountSearchQuery("")
                                }
                                Spacer()
                            }
                        }
                    }
                } else {
                    VStack(spacing: 8) {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DashboardTokens.Font.metadata().weight(.medium))
                .foregroundStyle(DashboardTokens.textSecondary)

            control()
        }
    }

    func expandableAccountRow(_ account: AccountUsage) -> some View {
        let isExpanded = expandedAccountNames.contains(account.name)

        return SettingsPanelCard(padding: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
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

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DashboardTokens.textTertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 14, height: 14)
                            .animation(.easeInOut(duration: 0.16), value: isExpanded)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    expandedAccountContent(account)
                        .padding(.top, 10)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                            )
                        )
                }
            }
        }
    }

    func expandedAccountContent(_ account: AccountUsage) -> some View {
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
