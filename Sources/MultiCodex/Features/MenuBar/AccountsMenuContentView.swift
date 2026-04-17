import AppKit
import SwiftUI

struct AccountsMenuContentView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel
    @Environment(\.openWindow) var openWindow
    @State var keyboardMonitor: Any?
    @State var expandedAccountNames: Set<String> = []
    @State var showAllAccounts = false

    var body: some View {
        ZStack(alignment: .bottom) {
            DashboardTokens.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: DashboardTokens.Spacing.sectionSpacing) {
                header

                if let alert = viewModel.prioritizedMenuAlert {
                    alertBanner(alert)
                }

                if viewModel.prioritizedMenuAlert == nil, let warning = viewModel.refreshWarningMessage {
                    SubtleWarningRow(text: warning)
                }

                if viewModel.accounts.isEmpty {
                    emptyStateCard
                } else {
                    bentoUsageSection

                    if !viewModel.menuListAccounts.isEmpty {
                        accountsSection
                    }
                }

                footer
            }
            .padding(DashboardTokens.Spacing.containerPadding)

            if let toast = activeToast {
                toastView(text: toast.text, color: toast.color)
                    .padding(DashboardTokens.Spacing.sectionSpacing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: viewModel.accounts.map(\.name)) { _ in
            let activeNames = Set(viewModel.accounts.map(\.name))
            expandedAccountNames = expandedAccountNames.intersection(activeNames)
            if !canToggleShowAll {
                showAllAccounts = false
            }
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.accounts.map(\.name))
        .animation(.easeInOut(duration: 0.18), value: viewModel.switchingAccountName)
        .animation(.easeInOut(duration: 0.18), value: viewModel.accountActionInFlightName)
        .animation(.easeInOut(duration: 0.18), value: expandedAccountNames)
        .animation(.easeInOut(duration: 0.18), value: showAllAccounts)
    }
}
