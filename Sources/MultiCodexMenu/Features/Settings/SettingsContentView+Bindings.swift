import SwiftUI

extension SettingsContentView {
    var sidebarSelectionBinding: Binding<SettingsSection?> {
        Binding(
            get: { viewModel.selectedSettingsSection },
            set: { newValue in
                guard let newValue else { return }
                viewModel.selectSettingsSection(newValue)
            }
        )
    }

    var accountSearchBinding: Binding<String> {
        Binding(
            get: { viewModel.accountSearchQuery },
            set: { viewModel.setAccountSearchQuery($0) }
        )
    }

    var menuDensityBinding: Binding<MenuDensity> {
        Binding(
            get: { viewModel.menuDensity },
            set: { viewModel.setMenuDensity($0) }
        )
    }

    var usageBarStyleBinding: Binding<UsageBarStyle> {
        Binding(
            get: { viewModel.usageBarStyle },
            set: { viewModel.setUsageBarStyle($0) }
        )
    }

    var limitsCacheTTLMinutesBinding: Binding<Int> {
        Binding(
            get: { viewModel.limitsCacheTTLMinutes },
            set: { viewModel.setLimitsCacheTTLSeconds($0 * 60) }
        )
    }

    var removalSheetBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingAccountRemovalRequest != nil },
            set: { isPresented in
                if !isPresented {
                    deleteConfirmationName = ""
                    viewModel.cancelPendingAccountRemoval()
                }
            }
        )
    }

    var isAccountActionRunning: Bool {
        viewModel.accountActionInFlightName != nil || viewModel.switchingAccountName != nil
    }

    var runtimeStatus: RuntimeStatusPresentation {
        AccountPresentation.runtimeStatus(
            summary: viewModel.runtimeProbeSummary,
            isAvailable: viewModel.isCodexRuntimeAvailable
        )
    }

    var testConfigToggleBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isUsingTemporaryAuthSandbox },
            set: { viewModel.setTemporaryAuthSandboxEnabled($0) }
        )
    }

    func renameBinding(for accountName: String) -> Binding<String> {
        Binding(
            get: { renameDrafts[accountName] ?? accountName },
            set: { renameDrafts[accountName] = $0 }
        )
    }

    func cannotRename(_ accountName: String) -> Bool {
        let raw = renameDrafts[accountName] ?? accountName
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == accountName
    }

    func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func syncRenameDrafts() {
        let names = Set(viewModel.accounts.map(\.name))
        renameDrafts = renameDrafts.filter { names.contains($0.key) }
        for account in viewModel.accounts where renameDrafts[account.name] == nil {
            renameDrafts[account.name] = account.name
        }
    }

    func isSelectedAccount(_ name: String) -> Bool {
        viewModel.selectedSettingsAccountName == name
    }

    func stepSymbol(_ step: OnboardingStep, isActive: Bool) -> String {
        if isActive {
            return "circle.fill"
        }
        switch step {
        case .done:
            return "checkmark.circle.fill"
        default:
            return "circle"
        }
    }

    func handleAlertAction(_ alert: MenuAlertState) {
        switch alert.action {
        case .openRuntimeSettings:
            viewModel.selectSettingsSection(.runtime)
        default:
            viewModel.performMenuAlertAction(alert.action)
        }
    }
}
