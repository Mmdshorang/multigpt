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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Group {
            if layout == .iconOnly {
                baseButton.help(title)
            } else {
                baseButton
            }
        }
    }

    private var baseButton: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(ActionPillPressStyle(reduceMotion: reduceMotion))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.40 : 1)
        .onHover { hovering in
            guard !isDisabled else { return }
            withAnimation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
        .contentShape(RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous))
    }

    @ViewBuilder
    private var buttonContent: some View {
        switch layout {
        case .titleAndIcon:
            Label(title, systemImage: symbol)
                .font(DashboardTokens.Font.button())
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minHeight: 30)
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
                .shadow(color: shadowColor, radius: role == .primary ? 5 : 0, y: role == .primary ? 2 : 0)
        case .iconOnly:
            Image(systemName: symbol)
                .font(DashboardTokens.Font.metadataBold())
                .frame(width: 24, height: 24)
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
                .shadow(color: shadowColor, radius: role == .primary ? 4 : 0, y: role == .primary ? 2 : 0)
        }
    }

    private var backgroundShape: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(role == .primary ? primaryBackground : secondaryBackground)

            if isHovered {
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                    .fill(Color.white.opacity(role == .primary ? 0.08 : 0.04))
            }
        }
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
            .stroke(
                role == .primary
                    ? DashboardTokens.accent.opacity(isHovered ? 0.56 : 0.42)
                    : (isHovered ? DashboardTokens.hoverBorder : borderColor),
                lineWidth: 0.5
            )
    }

    private var primaryBackground: LinearGradient {
        LinearGradient(
            colors: [
                DashboardTokens.accent.opacity(0.96),
                DashboardTokens.accent.opacity(0.86),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var secondaryBackground: LinearGradient {
        LinearGradient(
            colors: [
                DashboardTokens.cardBackgroundSubtle,
                DashboardTokens.cardBackgroundSubtle,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        DashboardTokens.cardBorder
    }

    private var foregroundColor: Color {
        if isHovered, role == .secondary {
            return DashboardTokens.textPrimary.opacity(1)
        }
        return role == .primary ? .white : DashboardTokens.textPrimary
    }

    private var shadowColor: Color {
        role == .primary ? DashboardTokens.accent.opacity(isHovered ? 0.28 : 0.20) : .clear
    }

    private var accessibilityHint: String {
        role == .primary ? "Primary action" : "Secondary action"
    }
}

private struct ActionPillPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.960 : 1)
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .animation(
                DashboardTokens.Motion.springPress(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
