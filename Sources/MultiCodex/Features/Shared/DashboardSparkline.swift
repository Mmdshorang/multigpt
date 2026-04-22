import SwiftUI

struct DashboardSparkline: View {
    let values: [Double]
    var height: CGFloat = DashboardTokens.Spacing.sparkHeight
    var barWidth: CGFloat = DashboardTokens.scaled(4)
    var barSpacing: CGFloat = DashboardTokens.scaled(2)
    var barRadius: CGFloat = DashboardTokens.scaled(1.5)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var maxValue: Double {
        values.max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let normalizedHeight = maxValue > 0 ? value / maxValue : 0
                let barHeight = max(DashboardTokens.scaled(2), CGFloat(normalizedHeight) * height)

                RoundedRectangle(cornerRadius: barRadius)
                    .fill(barColor(for: value))
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .frame(height: height)
        .animation(DashboardTokens.Motion.progress(reduceMotion: reduceMotion), value: values)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage trend chart")
        .accessibilityValue("Contains \(values.count) samples")
    }

    private func barColor(for value: Double) -> Color {
        let percent = maxValue > 0 ? value / maxValue * 100 : 0
        if percent > 80 {
            return DashboardTokens.sparkCritical
        }
        if percent > 60 {
            return DashboardTokens.sparkHigh
        }
        return DashboardTokens.sparkDefault
    }
}
