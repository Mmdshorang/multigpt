import SwiftUI

struct SettingsTextField: View {
    let placeholder: String
    var accessibilityLabel: String? = nil
    @Binding var text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(DashboardTokens.Font.metadata())
            .foregroundStyle(DashboardTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                    .fill(DashboardTokens.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                    .stroke(isFocused ? DashboardTokens.inputBorderFocused : DashboardTokens.inputBorder, lineWidth: 0.5)
            )
            .shadow(
                color: DashboardTokens.shadowColor.opacity(isFocused ? 0.16 : 0),
                radius: 6,
                y: 2
            )
            .focused($isFocused)
            .animation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion), value: isFocused)
            .accessibilityLabel(accessibilityLabel ?? placeholder)
    }
}
