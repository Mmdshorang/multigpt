import SwiftUI

struct SettingsToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(SettingsToggleStyle())
            .font(DashboardTokens.Font.metadata())
            .foregroundStyle(DashboardTokens.textPrimary)
            .accessibilityHint("Double tap to toggle")
    }
}

private struct SettingsToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: DashboardTokens.scaled(10)) {
                configuration.label

                Spacer(minLength: DashboardTokens.scaled(10))

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isOn ? DashboardTokens.toggleTrackOn : DashboardTokens.toggleTrackOff)
                    .frame(width: DashboardTokens.scaled(38), height: DashboardTokens.scaled(22))
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.22), radius: 3, y: 1)
                            .padding(2)
                            .offset(x: configuration.isOn ? DashboardTokens.scaled(8) : -DashboardTokens.scaled(8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(configuration.isOn ? DashboardTokens.accent.opacity(0.45) : DashboardTokens.cardBorder, lineWidth: 1)
                    )
            }
            .frame(minHeight: DashboardTokens.scaled(28))
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}
