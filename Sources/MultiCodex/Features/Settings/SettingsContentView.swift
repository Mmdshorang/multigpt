import SwiftUI

struct SettingsContentView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @ObservedObject var viewModel: AccountsMenuViewModel

    @State var codexPathDraft = ""
    @State var renameDrafts: [String: String] = [:]
    @State var expandedAccountNames: Set<String> = []
    @State var sequentialLoginCountText = "1"
    @State private var hoveredSidebarSection: SettingsSection?
    @State var pendingRemovalAccountName: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(
                    minWidth: 200,
                    idealWidth: 220
                )
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
            syncExpandedAccounts()
        }
        .onChange(of: viewModel.customCodexPath) { codexPathDraft = $0 }
        .onChange(of: viewModel.accounts.map(\.name)) { _ in
            syncRenameDrafts()
            syncExpandedAccounts()
        }
    }

    var sidebarBackground: some View {
        LinearGradient(
            colors: [DashboardTokens.backgroundTop, DashboardTokens.background],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DashboardTokens.accentBackground)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "terminal.fill")
                                .font(DashboardTokens.Font.title())
                                .foregroundStyle(DashboardTokens.accent)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("MultiCodex")
                            .font(DashboardTokens.Font.title())
                            .foregroundStyle(DashboardTokens.textPrimary)
                        Text("Preferences")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                    }
                }

                settingsInsetPanel {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            DashboardSectionHeader(title: "Runtime")
                            Text(runtimeStatus.text)
                                .font(DashboardTokens.Font.metadata().weight(.semibold))
                                .foregroundStyle(DashboardTokens.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        settingsBadge(
                            text: viewModel.isCodexRuntimeAvailable ? "Ready" : "Attention",
                            symbol: runtimeStatus.symbol,
                            color: runtimeStatus.color
                        )
                    }
                }
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sections")
                    .font(DashboardTokens.Font.sectionLabel())
                    .tracking(0.5)
                    .foregroundStyle(DashboardTokens.textTertiary)
                    .padding(.horizontal, 12)

                VStack(spacing: 3) {
                    ForEach(viewModel.settingsSections) { section in
                        sidebarRow(section)
                    }
                }
                .padding(.horizontal, 6)
            }

            Spacer()
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func sidebarRow(_ section: SettingsSection) -> some View {
        let isSelected = viewModel.selectedSettingsSection == section
        let isHovered = hoveredSidebarSection == section

        Button {
            viewModel.selectSettingsSection(section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(DashboardTokens.Font.bodySemibold())
                    .foregroundStyle(isSelected ? DashboardTokens.accent : DashboardTokens.textSecondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(DashboardTokens.Font.bodySemibold())
                        .foregroundStyle(isSelected ? DashboardTokens.textPrimary : DashboardTokens.textSecondary)

                    if isSelected {
                        Text(selectedSectionSubtitle(for: section))
                            .font(DashboardTokens.Font.captionRegular())
                            .foregroundStyle(DashboardTokens.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? DashboardTokens.sidebarSelectedBackground : (isHovered ? DashboardTokens.sidebarHoverBackground : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? DashboardTokens.accent.opacity(0.16) : Color.clear, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            hoveredSidebarSection = hovering ? section : nil
        }
        .animation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion), value: isHovered)
        .animation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion), value: isSelected)
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
                case .data:
                    dataPage
                case .about:
                    aboutPage
                }
            }
            .frame(maxWidth: settingsContentMaxWidth, alignment: .leading)
            .padding(.horizontal, DashboardTokens.Spacing.contentPadding)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private var dataPage: some View {
        DataPane(viewModel: viewModel)
    }

    private func selectedSectionSubtitle(for section: SettingsSection) -> String {
        switch section {
        case .general: return "Overview and behavior"
        case .accounts: return "Identity and usage"
        case .system: return "Runtime and diagnostics"
        case .data: return "Backup and restore"
        case .about: return "Version and support"
        }
    }
}
