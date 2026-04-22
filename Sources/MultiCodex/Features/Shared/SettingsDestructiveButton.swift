import SwiftUI

struct SettingsDestructiveButton: View {
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DashboardTokens.Font.button())
                .foregroundStyle(isDisabled ? DashboardTokens.textTertiary : DashboardTokens.destructive)
                .padding(.horizontal, DashboardTokens.scaled(10))
                .padding(.vertical, DashboardTokens.scaled(7))
                .background(
                    RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                        .fill(isDisabled ? Color.clear : DashboardTokens.destructiveBackground.opacity(0.6))
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
    }
}
