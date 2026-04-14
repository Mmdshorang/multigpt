import AppKit
import SwiftUI

struct AccountsMenuContentView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel
    @Environment(\.openWindow) var openWindow
    @State var selectedAccountName: String?
    @State var keyboardMonitor: Any?
    @State var expandedAccountNames: Set<String> = []

    struct MenuLayoutTokens {
        let containerPadding: CGFloat
        let sectionSpacing: CGFloat
        let cardPadding: CGFloat
        let cardCornerRadius: CGFloat
        let cardBorderOpacity: Double
        let rowListSpacing: CGFloat
        let rowHorizontalPadding: CGFloat
        let rowVerticalPadding: CGFloat
        let rowCornerRadius: CGFloat
        let rowSelectedFillOpacity: Double
        let rowDefaultFillOpacity: Double
        let rowSelectedBorderOpacity: Double
        let rowDefaultBorderOpacity: Double
        let footerSpacing: CGFloat
        let toastOuterPadding: CGFloat
        let toastHorizontalPadding: CGFloat
        let toastVerticalPadding: CGFloat

        static func forDensity(_ density: MenuDensity) -> Self {
            switch density {
            case .compact:
                return MenuLayoutTokens(
                    containerPadding: 8,
                    sectionSpacing: 8,
                    cardPadding: 9,
                    cardCornerRadius: 9,
                    cardBorderOpacity: 0.10,
                    rowListSpacing: 7,
                    rowHorizontalPadding: 7,
                    rowVerticalPadding: 6,
                    rowCornerRadius: 7,
                    rowSelectedFillOpacity: 0.10,
                    rowDefaultFillOpacity: 0.05,
                    rowSelectedBorderOpacity: 0.34,
                    rowDefaultBorderOpacity: 0.08,
                    footerSpacing: 8,
                    toastOuterPadding: 8,
                    toastHorizontalPadding: 8,
                    toastVerticalPadding: 6
                )
            case .comfortable:
                return MenuLayoutTokens(
                    containerPadding: 12,
                    sectionSpacing: 10,
                    cardPadding: 10,
                    cardCornerRadius: 10,
                    cardBorderOpacity: 0.14,
                    rowListSpacing: 7,
                    rowHorizontalPadding: 8,
                    rowVerticalPadding: 6,
                    rowCornerRadius: 8,
                    rowSelectedFillOpacity: 0.12,
                    rowDefaultFillOpacity: 0.06,
                    rowSelectedBorderOpacity: 0.48,
                    rowDefaultBorderOpacity: 0.10,
                    footerSpacing: 10,
                    toastOuterPadding: 12,
                    toastHorizontalPadding: 10,
                    toastVerticalPadding: 7
                )
            }
        }
    }

    var layout: MenuLayoutTokens {
        .forDensity(viewModel.menuDensity)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
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
                    if let current = viewModel.currentAccount {
                        currentAccountCard(current)
                    }
                    if !viewModel.menuListAccounts.isEmpty {
                        quickAccountsCard
                    }
                }

                footer
            }
            .padding(layout.containerPadding)

            if let toast = activeToast {
                toastView(text: toast.text, color: toast.color)
                    .padding(layout.toastOuterPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            synchronizeSelection()
            installKeyboardMonitor()
        }
        .onDisappear {
            removeKeyboardMonitor()
        }
        .onChange(of: viewModel.accounts.map(\.name)) { _ in
            let activeNames = Set(viewModel.accounts.map(\.name))
            expandedAccountNames = expandedAccountNames.intersection(activeNames)
            synchronizeSelection()
        }
        .onChange(of: viewModel.focusedAccountName) { _ in
            synchronizeSelection()
        }
        .animation(.easeInOut(duration: 0.18), value: viewModel.accounts.map(\.name))
        .animation(.easeInOut(duration: 0.18), value: viewModel.switchingAccountName)
        .animation(.easeInOut(duration: 0.18), value: viewModel.accountActionInFlightName)
        .animation(.easeInOut(duration: 0.18), value: expandedAccountNames)
    }
}
