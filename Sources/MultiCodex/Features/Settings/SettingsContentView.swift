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
                    minWidth: DashboardTokens.scaled(220),
                    idealWidth: DashboardTokens.scaled(236)
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
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(18)) {
            VStack(alignment: .leading, spacing: DashboardTokens.scaled(14)) {
                HStack(spacing: DashboardTokens.scaled(12)) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DashboardTokens.accentBackground)
                        .frame(width: DashboardTokens.scaled(40), height: DashboardTokens.scaled(40))
                        .overlay(
                            Image(systemName: "terminal.fill")
                                .font(.system(size: DashboardTokens.scaled(17), weight: .semibold))
                                .foregroundStyle(DashboardTokens.accent)
                        )

                    VStack(alignment: .leading, spacing: DashboardTokens.scaled(3)) {
                        Text("MultiCodex")
                            .font(.system(size: DashboardTokens.scaled(16), weight: .semibold))
                            .foregroundStyle(DashboardTokens.textPrimary)
                        Text("Preferences")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                    }
                }

                settingsInsetPanel {
                    VStack(alignment: .leading, spacing: DashboardTokens.scaled(10)) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: DashboardTokens.scaled(4)) {
                                DashboardSectionHeader(title: "Runtime")
                                Text(runtimeStatus.text)
                                    .font(DashboardTokens.Font.metadata().weight(.semibold))
                                    .foregroundStyle(DashboardTokens.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: DashboardTokens.scaled(8))

                            settingsBadge(text: viewModel.isCodexRuntimeAvailable ? "Ready" : "Needs Attention", symbol: runtimeStatus.symbol, color: runtimeStatus.color)
                        }

                        Text("Manage accounts, sorting, and automation.")
                            .font(DashboardTokens.Font.metadata())
                            .foregroundStyle(DashboardTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, DashboardTokens.scaled(14))

            VStack(alignment: .leading, spacing: DashboardTokens.scaled(6)) {
                Text("Sections")
                    .font(DashboardTokens.Font.sectionLabel())
                    .tracking(1.0)
                    .foregroundStyle(DashboardTokens.textTertiary)
                    .padding(.horizontal, DashboardTokens.scaled(14))

                VStack(spacing: DashboardTokens.scaled(4)) {
                    ForEach(viewModel.settingsSections) { section in
                        sidebarRow(section)
                    }
                }
                .padding(.horizontal, DashboardTokens.scaled(8))
            }

            Spacer()
        }
        .padding(.vertical, DashboardTokens.scaled(14))
    }

    @ViewBuilder
    private func sidebarRow(_ section: SettingsSection) -> some View {
        let isSelected = viewModel.selectedSettingsSection == section
        let isHovered = hoveredSidebarSection == section

        Button {
            viewModel.selectSettingsSection(section)
        } label: {
            HStack(spacing: DashboardTokens.scaled(12)) {
                Image(systemName: section.symbol)
                    .font(.system(size: DashboardTokens.scaled(13), weight: .semibold))
                    .foregroundStyle(isSelected ? DashboardTokens.accent : DashboardTokens.textSecondary)
                    .frame(width: DashboardTokens.scaled(18))

                VStack(alignment: .leading, spacing: DashboardTokens.scaled(1)) {
                    Text(section.title)
                        .font(.system(size: DashboardTokens.scaled(13), weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? DashboardTokens.textPrimary : DashboardTokens.textSecondary)

                    if isSelected {
                        Text(selectedSectionSubtitle(for: section))
                            .font(.system(size: DashboardTokens.scaled(10), weight: .regular))
                            .foregroundStyle(DashboardTokens.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DashboardTokens.scaled(8))
            }
            .padding(.horizontal, DashboardTokens.scaled(12))
            .padding(.vertical, DashboardTokens.scaled(10))
            .background(
                RoundedRectangle(cornerRadius: DashboardTokens.scaled(14), style: .continuous)
                    .fill(isSelected ? DashboardTokens.sidebarSelectedBackground : (isHovered ? DashboardTokens.sidebarHoverBackground : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTokens.scaled(14), style: .continuous)
                    .stroke(isSelected ? DashboardTokens.accent.opacity(0.18) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DashboardTokens.scaled(14), style: .continuous))
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
            VStack(alignment: .leading, spacing: DashboardTokens.scaled(18)) {
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
            .padding(.horizontal, DashboardTokens.Spacing.contentPadding)
            .padding(.vertical, DashboardTokens.scaled(22))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func selectedSectionSubtitle(for section: SettingsSection) -> String {
        switch section {
        case .general:
            return "Overview and behavior"
        case .accounts:
            return "Identity and usage"
        case .system:
            return "Runtime and diagnostics"
        case .about:
            return "Version and support"
        }
    }
}
