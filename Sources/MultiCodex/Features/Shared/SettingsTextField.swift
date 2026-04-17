import SwiftUI

struct SettingsTextField: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(DashboardTokens.Font.metadata())
            .foregroundStyle(DashboardTokens.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DashboardTokens.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFocused ? DashboardTokens.inputBorderFocused : DashboardTokens.inputBorder, lineWidth: 1)
            )
            .focused($isFocused)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
