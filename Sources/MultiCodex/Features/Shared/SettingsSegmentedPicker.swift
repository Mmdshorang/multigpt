import SwiftUI

struct SettingsSegmentedPicker<T: Hashable>: View {
    let options: [T]
    let titleForOption: (T) -> String
    @Binding var selection: T

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredOption: T?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                let isHovered = hoveredOption == option

                Button {
                    withAnimation(DashboardTokens.Motion.hover(reduceMotion: reduceMotion)) {
                        selection = option
                    }
                } label: {
                    Text(titleForOption(option))
                        .font(DashboardTokens.Font.metadata().weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .allowsTightening(true)
                        .foregroundStyle(isSelected ? DashboardTokens.textPrimary : DashboardTokens.textSecondary)
                        .padding(.horizontal, DashboardTokens.scaled(10))
                        .padding(.vertical, DashboardTokens.scaled(6))
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.smallRadius, style: .continuous)
                                .fill(isSelected ? DashboardTokens.segmentedActiveBackground : (isHovered ? DashboardTokens.segmentedInactiveBackground : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.smallRadius, style: .continuous)
                                .stroke(isSelected ? DashboardTokens.segmentedActiveBorder : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: DashboardTokens.Spacing.smallRadius, style: .continuous))
                .accessibilityLabel(titleForOption(option))
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .onHover { hovering in
                    hoveredOption = hovering ? option : nil
                }
            }
        }
        .padding(DashboardTokens.scaled(3))
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .fill(DashboardTokens.segmentedTrackBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.controlRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }
}
