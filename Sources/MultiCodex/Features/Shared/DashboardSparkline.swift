import SwiftUI

struct DashboardSparkline: View {
    let values: [Double]
    var height: CGFloat = DashboardTokens.Spacing.sparkHeight
    var barWidth: CGFloat = 4
    var barSpacing: CGFloat = 2
    var barRadius: CGFloat = 1.5

    private var maxValue: Double {
        values.max() ?? 1
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let normalizedHeight = maxValue > 0 ? value / maxValue : 0
                let barHeight = max(2, CGFloat(normalizedHeight) * height)

                RoundedRectangle(cornerRadius: barRadius)
                    .fill(barColor(for: value))
                    .frame(width: barWidth, height: barHeight)
            }
        }
        .frame(height: height)
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
