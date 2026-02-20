import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel

    @State var codexPathDraft = ""
    @State var renameDrafts: [String: String] = [:]
    @State var deleteConfirmationName = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            codexPathDraft = viewModel.customCodexPath
            syncRenameDrafts()
            if viewModel.selectedSettingsSection == .advanced, !viewModel.isAdvancedSettingsVisible {
                viewModel.setAdvancedSettingsVisible(true)
            }
        }
        .onChange(of: viewModel.customCodexPath) { codexPathDraft = $0 }
        .onChange(of: viewModel.accounts.map(\.name)) { _ in
            syncRenameDrafts()
        }
        .sheet(isPresented: removalSheetBinding) {
            removalConfirmationSheet
        }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: sidebarSelectionBinding) {
                ForEach(viewModel.settingsSections) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }

            Divider()

            HStack {
                if viewModel.isAdvancedSettingsVisible {
                    Button("Hide Advanced") {
                        viewModel.setAdvancedSettingsVisible(false)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                } else {
                    Button("Show Advanced") {
                        viewModel.setAdvancedSettingsVisible(true)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                Spacer()
            }
            .padding(10)
        }
    }

    @ViewBuilder
    var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard

                switch viewModel.selectedSettingsSection {
                case .dashboard:
                    dashboardPage
                case .accounts:
                    accountsPage
                case .runtime:
                    runtimePage
                case .display:
                    displayPage
                case .troubleshooting:
                    troubleshootingPage
                case .advanced:
                    if viewModel.isAdvancedSettingsVisible {
                        advancedPage
                    } else {
                        hiddenAdvancedPage
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}
