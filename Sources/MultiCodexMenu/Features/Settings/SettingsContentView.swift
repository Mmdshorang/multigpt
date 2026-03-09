import SwiftUI

struct SettingsContentView: View {
    @ObservedObject var viewModel: AccountsMenuViewModel

    @State var codexPathDraft = ""
    @State var renameDrafts: [String: String] = [:]
    @State var deleteConfirmationName = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 268, idealWidth: 288)
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

    var sidebarBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .underPageBackgroundColor),
                Color(nsColor: .windowBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                Text("Tune MultiCodex for daily usage, account management, and local diagnostics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    AccountStatusPill(text: runtimeStatus.text, color: runtimeStatus.color)
                    Text(viewModel.lastUpdatedLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.settingsSections) { section in
                        sidebarSectionRow(section)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            SettingsPanelCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Advanced Tools")
                                .font(.subheadline.weight(.semibold))
                            Text("Keep these controls tucked away unless you need them.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Button(viewModel.isAdvancedSettingsVisible ? "Hide" : "Show") {
                            viewModel.setAdvancedSettingsVisible(!viewModel.isAdvancedSettingsVisible)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }

                    if viewModel.isAdvancedSettingsVisible {
                        settingsInfoRow(symbol: "checkmark.circle.fill", text: "Advanced section is available in the sidebar.", color: .green)
                    } else {
                        settingsInfoRow(symbol: "eye.slash", text: "Advanced section is currently hidden.", color: .secondary)
                    }
                }
            }
        }
        .padding(16)
    }

    func sidebarSectionRow(_ section: SettingsSection) -> some View {
        Button {
            viewModel.selectSettingsSection(section)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isSidebarSectionSelected(section) ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                        .frame(width: 34, height: 34)

                    Image(systemName: section.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSidebarSectionSelected(section) ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(section.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isSidebarSectionSelected(section) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSidebarSectionSelected(section) ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSidebarSectionSelected(section) ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            .frame(maxWidth: settingsContentMaxWidth, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    func isSidebarSectionSelected(_ section: SettingsSection) -> Bool {
        viewModel.selectedSettingsSection == section
    }
}
