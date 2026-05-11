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
            HStack(spacing: 10) {
                configuration.label

                Spacer(minLength: 10)

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(configuration.isOn ? DashboardTokens.toggleTrackOn : DashboardTokens.toggleTrackOff)
                    .frame(width: 36, height: 20)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.20), radius: 2, y: 1)
                            .padding(2)
                            .offset(x: configuration.isOn ? 8 : -8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(configuration.isOn ? DashboardTokens.accent.opacity(0.42) : DashboardTokens.cardBorder, lineWidth: 0.5)
                    )
            }
            .frame(minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}
