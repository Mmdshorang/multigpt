import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel

    @State var codexPathDraft = ""
    @State var renameDrafts: [String: String] = [:]
    @State var removalDeleteDataChoice: [String: Bool] = [:]

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 168, idealWidth: 176)
                .background(sidebarBackground)
        } detail: {
            ZStack {
                settingsBackground

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(settingsBackground)
        .onAppear {
            codexPathDraft = viewModel.customCodexPath
            syncRenameDrafts()
            syncRemovalChoices()
            if viewModel.selectedSettingsSection == .advanced {
                viewModel.setAdvancedSettingsVisible(true)
            }
        }
        .onChange(of: viewModel.customCodexPath) { codexPathDraft = $0 }
        .onChange(of: viewModel.accounts.map(\.name)) { _ in
            syncRenameDrafts()
            syncRemovalChoices()
        }
    }

    var sidebarBackground: some View {
        Color(nsColor: .underPageBackgroundColor)
        .ignoresSafeArea()
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.headline)

                HStack(spacing: 8) {
                    AccountStatusPill(text: runtimeStatus.text, color: runtimeStatus.color)
                }
            }
            .padding(.horizontal, 10)

            List(selection: sidebarSelectionBinding) {
                ForEach(viewModel.settingsSections) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)

            SettingsPanelCard(padding: 10) {
                HStack {
                    Text("Advanced")
                        .font(.caption.weight(.semibold))

                    Spacer(minLength: 8)

                    Button(viewModel.isAdvancedSettingsVisible ? "Hide" : "Show") {
                        viewModel.setAdvancedSettingsVisible(!viewModel.isAdvancedSettingsVisible)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                switch viewModel.selectedSettingsSection {
                case .dashboard:
                    VStack(alignment: .leading, spacing: 10) {
                        headerCard
                        dashboardPage
                    }
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
            .frame(maxWidth: settingsContentMaxWidth, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}
