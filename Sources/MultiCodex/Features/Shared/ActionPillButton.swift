import SwiftUI

enum ActionPillRole {
    case primary
    case secondary
}

enum ActionPillLayout {
    case titleAndIcon
    case iconOnly
}

struct ActionPillButton: View {
    let title: String
    let symbol: String
    var role: ActionPillRole = .secondary
    var layout: ActionPillLayout = .titleAndIcon
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(title)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var buttonContent: some View {
        switch layout {
        case .titleAndIcon:
            Label(title, systemImage: symbol)
                .font(DashboardTokens.Font.button().weight(role == .primary ? .semibold : .medium))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
        case .iconOnly:
            Image(systemName: symbol)
                .font(DashboardTokens.Font.button().weight(role == .primary ? .semibold : .medium))
                .frame(width: 16, height: 16)
                .padding(6)
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
            .fill(
                role == .primary
                    ? AnyShapeStyle(primaryBackground)
                    : AnyShapeStyle(secondaryBackground)
            )
    }

    private var primaryBackground: Color {
        isHovered ? DashboardTokens.accent.opacity(0.9) : DashboardTokens.accent
    }

    private var secondaryBackground: Color {
        isHovered ? Color.white.opacity(0.05) : DashboardTokens.cardBackground
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
            .stroke(
                role == .primary
                    ? DashboardTokens.accent.opacity(0.4)
                    : borderColor,
                lineWidth: 1
            )
    }

    private var borderColor: Color {
        isHovered ? Color.white.opacity(0.12) : DashboardTokens.cardBorder
    }

    private var foregroundColor: Color {
        role == .primary ? .white : DashboardTokens.textSecondary
    }
}
