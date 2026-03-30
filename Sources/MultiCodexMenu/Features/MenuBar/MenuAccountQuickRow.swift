import SwiftUI

struct MenuAccountQuickRow: View {
    let row: AccountRowState
    let layout: AccountsMenuContentView.MenuLayoutTokens
    let isSelected: Bool
    let isExpanded: Bool
    let fiveHourProgressValue: Double
    let weeklyProgressValue: Double
    let isBusy: Bool
    let isSwitching: Bool
    let isAuthRunning: Bool
    let onSelect: () -> Void
    let onPrimaryAction: () -> Void
    let onToggleExpanded: () -> Void

    var isPrimaryActionInProgress: Bool {
        switch row.primaryAction {
        case .switchAccount:
            return isSwitching
        case .relogin:
            return isAuthRunning
        case .none:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: max(4, layout.sectionSpacing - 3)) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if row.isCurrent {
                            AccountStatusPill(text: "Current", color: .accentColor)
                        }
                        AccountStatusPill(
                            text: row.connectionState.label,
                            color: AccountPresentation.statusColor(for: row.connectionState)
                        )
                    }

                    HStack(spacing: 8) {
                        Text("5h \(row.fiveHourPercent)")
                        Text("weekly \(row.weeklyPercent)")
                        Text(row.resetText)
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if row.connectionState != .connected, let hint = row.account.connectionHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(AccountPresentation.statusColor(for: row.connectionState))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isSelected, row.primaryAction != .none {
                    if isPrimaryActionInProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        ActionPillButton(
                            title: row.primaryAction.title,
                            symbol: row.primaryAction.symbol,
                            role: .secondary,
                            layout: .iconOnly,
                            isDisabled: isBusy,
                            action: onPrimaryAction
                        )
                        .help(row.primaryAction.title)
                    }
                }

                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide remaining limit" : "Show remaining limit")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: max(6, layout.sectionSpacing - 2)) {
                        AccountUsageMetricCard(
                            title: "5h",
                            metric: row.account.usage.fiveHour,
                            resetDisplayMode: row.resetDisplayMode,
                            progressValue: fiveHourProgressValue
                        )
                        AccountUsageMetricCard(
                            title: "weekly",
                            metric: row.account.usage.weekly,
                            resetDisplayMode: row.resetDisplayMode,
                            progressValue: weeklyProgressValue
                        )
                    }

                    if row.connectionState == .connected, let hint = row.account.connectionHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(AccountPresentation.statusColor(for: row.connectionState))
                            .lineLimit(2)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, layout.rowHorizontalPadding)
        .padding(.vertical, layout.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(isSelected ? layout.rowSelectedFillOpacity : layout.rowDefaultFillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(layout.rowSelectedBorderOpacity) : Color.secondary.opacity(layout.rowDefaultBorderOpacity),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .zIndex(isExpanded ? 1 : 0)
    }

}
