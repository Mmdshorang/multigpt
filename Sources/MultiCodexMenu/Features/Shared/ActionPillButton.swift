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
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
        case .iconOnly:
            Image(systemName: symbol)
                .font(.caption.weight(role == .primary ? .semibold : .medium))
                .frame(width: 16, height: 16)
                .padding(6)
                .background(backgroundShape)
                .overlay(borderShape)
                .foregroundStyle(foregroundColor)
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                role == .primary
                    ? AnyShapeStyle(
                        Color.accentColor
                    )
                    : AnyShapeStyle(
                        Color(nsColor: .controlBackgroundColor).opacity(0.72)
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
}
