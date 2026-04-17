import SwiftUI

struct SettingsSegmentedPicker<T: Hashable>: View {
    let options: [T]
    let titleForOption: (T) -> String
    @Binding var selection: T

    @State private var hoveredOption: T?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                let isHovered = hoveredOption == option

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = option
                    }
                } label: {
                    Text(titleForOption(option))
                        .font(DashboardTokens.Font.metadata().weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? DashboardTokens.textPrimary : DashboardTokens.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? DashboardTokens.segmentedActiveBackground : (isHovered ? Color.white.opacity(0.04) : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isSelected ? DashboardTokens.segmentedActiveBorder : Color.clear, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredOption = hovering ? option : nil
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DashboardTokens.segmentedTrackBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }
}
