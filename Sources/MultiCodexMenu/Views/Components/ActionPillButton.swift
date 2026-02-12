import SwiftUI

struct ActionPillButton: View {
    let title: String
    let symbol: String
    var prominent: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(prominent ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(prominent ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .foregroundStyle(prominent ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}
