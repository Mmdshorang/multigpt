import SwiftUI

struct SettingsContentView: View {
    @Environment(\.openWindow) var openWindow

    @ObservedObject var viewModel: AccountsMenuViewModel

    @State var codexPathDraft = ""
    @State var renameDrafts: [String: String] = [:]
    @State var removalDeleteDataChoice: [String: Bool] = [:]
    @State var expandedAccountNames: Set<String> = []
    @State var sequentialLoginCountText = "1"

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 160, idealWidth: 170)
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
            syncExpandedAccounts()
        }
        .onChange(of: viewModel.customCodexPath) { codexPathDraft = $0 }
        .onChange(of: viewModel.accounts.map(\.name)) { _ in
            syncRenameDrafts()
            syncRemovalChoices()
            syncExpandedAccounts()
        }
    }

    var sidebarBackground: some View {
        Color(red: 0.06, green: 0.07, blue: 0.10)
        .ignoresSafeArea()
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SETTINGS")
                    .font(DashboardTokens.Font.sectionLabel())
                    .tracking(1.5)
                    .foregroundStyle(DashboardTokens.textTertiary)

                AccountStatusPill(text: runtimeStatus.text, color: runtimeStatus.color)
            }
            .padding(.horizontal, 12)

            VStack(spacing: 2) {
                ForEach(viewModel.settingsSections) { section in
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, 6)

            Spacer()
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func sidebarRow(_ section: SettingsSection) -> some View {
        let isSelected = viewModel.selectedSettingsSection == section

        Button {
            viewModel.selectSettingsSection(section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? DashboardTokens.accent : DashboardTokens.textSecondary)
                    .frame(width: 16)

                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DashboardTokens.textPrimary : DashboardTokens.textSecondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? DashboardTokens.sidebarSelectedBackground : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.selectedSettingsSection {
                case .general:
                    generalPage
                case .accounts:
                    accountsPage
                case .system:
                    systemPage
                case .about:
                    aboutPage
                }
            }
            .frame(maxWidth: settingsContentMaxWidth, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}
