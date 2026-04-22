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
        .opacity(isDisabled ? 0.42 : 1)
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
                .padding(.horizontal, DashboardTokens.scaled(10))
                .padding(.vertical, DashboardTokens.scaled(7))
                .frame(minHeight: DashboardTokens.scaled(30))
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
                .shadow(color: shadowColor, radius: role == .primary ? 6 : 0, y: role == .primary ? 3 : 0)
        case .iconOnly:
            Image(systemName: symbol)
                .font(.system(size: DashboardTokens.scaled(12), weight: .semibold))
                .frame(width: DashboardTokens.scaled(30), height: DashboardTokens.scaled(30))
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
                .shadow(color: shadowColor, radius: role == .primary ? 5 : 0, y: role == .primary ? 2 : 0)
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
            .fill(role == .primary ? primaryBackground : secondaryBackground)
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
            .stroke(role == .primary ? DashboardTokens.accent.opacity(0.45) : borderColor, lineWidth: 1)
    }

    private var primaryBackground: LinearGradient {
        LinearGradient(
            colors: [
                DashboardTokens.accent.opacity(0.98),
                DashboardTokens.accent.opacity(0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var secondaryBackground: LinearGradient {
        LinearGradient(
            colors: [
                DashboardTokens.cardBackgroundSubtle,
                DashboardTokens.cardBackgroundSubtle
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        DashboardTokens.cardBorder
    }

    private var foregroundColor: Color {
        role == .primary ? .white : DashboardTokens.textPrimary
    }

    private var shadowColor: Color {
        role == .primary ? DashboardTokens.accent.opacity(0.22) : .clear
    }

    private var accessibilityHint: String {
        role == .primary ? "Primary action" : "Secondary action"
    }
}

private struct ActionPillPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(
                DashboardTokens.Motion.springPress(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
