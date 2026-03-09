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

    var body: some View {
        Button(action: action) {
            buttonContent
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var buttonContent: some View {
        switch layout {
        case .titleAndIcon:
            Label(title, systemImage: symbol)
                .font(.caption.weight(role == .primary ? .semibold : .medium))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
                .shadow(color: shadowColor, radius: 7, x: 0, y: 2)
        case .iconOnly:
            Image(systemName: symbol)
                .font(.caption.weight(role == .primary ? .semibold : .medium))
                .frame(width: 16, height: 16)
                .padding(8)
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
                .shadow(color: shadowColor, radius: 7, x: 0, y: 2)
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                role == .primary
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.82),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor),
                                Color(nsColor: .windowBackgroundColor).opacity(0.86),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(role == .primary ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.08), lineWidth: 1)
    }

    private var foregroundColor: Color {
        role == .primary ? .white : .primary
    }

    private var shadowColor: Color {
        role == .primary ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.04)
    }
}
