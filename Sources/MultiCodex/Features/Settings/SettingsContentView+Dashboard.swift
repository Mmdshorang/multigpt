import SwiftUI

extension SettingsContentView {
    // MARK: - Dashboard Page

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

            onboardingWizardCard
        }
    }

    func dashboardMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            DashboardSectionHeader(title: title)

            Text(value)
                .font(DashboardTokens.Font.cardHeading())
                .foregroundStyle(DashboardTokens.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DashboardTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    func dashboardAlert(_ alert: MenuAlertState) -> some View {
        AlertActionCard(alert: alert) {
            handleAlertAction(alert)
        }
    }

    // MARK: - Onboarding Wizard

    var onboardingWizardCard: some View {
        SettingsPanelCard {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro(
                    title: "First-Run Setup",
                    description: viewModel.onboardingState.isComplete
                        ? "Setup is complete. Reset the wizard to walk through the steps again."
                        : "Finish the initial setup."
                )

                VStack(alignment: .leading, spacing: 6) {
                    onboardingStepRow(.runtime, isActive: viewModel.onboardingState.step == .runtime)
                    onboardingStepRow(.login, isActive: viewModel.onboardingState.step == .login)
                    onboardingStepRow(.verify, isActive: viewModel.onboardingState.step == .verify)
                    onboardingStepRow(.done, isActive: viewModel.onboardingState.step == .done)
                }

                if viewModel.onboardingState.isComplete {
                    Text("You can keep using MultiCodex as-is or use Reset Wizard to revisit the guided setup flow.")
                        .font(DashboardTokens.Font.metadata())
                        .foregroundStyle(DashboardTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                        ActionPillButton(title: "Reset Wizard", symbol: "arrow.counterclockwise") {
                            viewModel.resetOnboardingWizard()
                        }
                    }
                }
            }
        }
    }

    func onboardingStepRow(_ step: OnboardingStep, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: stepSymbol(step, isActive: isActive))
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(isActive ? DashboardTokens.accent : DashboardTokens.textSecondary)
                .frame(width: 18)

            Text(step.title)
                .font(DashboardTokens.Font.metadata().weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? DashboardTokens.textPrimary : DashboardTokens.textSecondary)

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
