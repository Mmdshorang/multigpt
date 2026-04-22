import SwiftUI

struct SettingsDestructiveButton: View {
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DashboardTokens.Font.button())
                .foregroundStyle(isDisabled ? DashboardTokens.textTertiary : DashboardTokens.destructive)
                .padding(.horizontal, DashboardTokens.scaled(10))
                .padding(.vertical, DashboardTokens.scaled(7))
                .background(
                    RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                        .fill(isDisabled ? Color.clear : (isHovered ? DashboardTokens.destructiveBackground : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                        .stroke(isDisabled ? DashboardTokens.cardBorder : DashboardTokens.destructiveBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .accessibilityHint("Destructive action")
        .onHover { isHovered = $0 }
        .animation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion), value: isHovered)
    }
}
