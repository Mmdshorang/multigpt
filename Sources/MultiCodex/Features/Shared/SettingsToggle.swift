import SwiftUI

struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(SettingsToggleStyle())
            .font(DashboardTokens.Font.metadata())
            .foregroundStyle(DashboardTokens.textPrimary)
    }
}

private struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label

                Spacer()

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isOn ? DashboardTokens.toggleTrackOn : DashboardTokens.toggleTrackOff)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.25), radius: 1, y: 1)
                            .padding(2)
                            .offset(x: configuration.isOn ? 7 : -7)
                    )
                    .frame(width: 36, height: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(configuration.isOn ? DashboardTokens.accent.opacity(0.5) : DashboardTokens.cardBorder, lineWidth: 1)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
