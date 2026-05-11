import SwiftUI

struct SettingsSegmentedPicker<T: Hashable>: View {
    let options: [T]
    let titleForOption: (T) -> String
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option

                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selection = option
                    }
                } label: {
                    Text(titleForOption(option))
                        .font(DashboardTokens.Font.metadata().weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .allowsTightening(true)
                        .foregroundStyle(isSelected ? DashboardTokens.textPrimary : DashboardTokens.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.smallRadius, style: .continuous)
                                .fill(isSelected ? DashboardTokens.segmentedActiveBackground : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.smallRadius, style: .continuous)
                                .stroke(isSelected ? DashboardTokens.segmentedActiveBorder : Color.clear, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: DashboardTokens.Spacing.smallRadius, style: .continuous))
                .accessibilityLabel(titleForOption(option))
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(DashboardTokens.segmentedTrackBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 0.5)
        )
    }
}
