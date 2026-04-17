import SwiftUI

struct SettingsDestructiveButton: View {
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DashboardTokens.Font.metadata().weight(.semibold))
                .foregroundStyle(isDisabled ? DashboardTokens.textTertiary : DashboardTokens.destructive)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isDisabled ? Color.clear : (isHovered ? DashboardTokens.destructiveBackground : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isDisabled ? DashboardTokens.cardBorder : DashboardTokens.destructiveBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
