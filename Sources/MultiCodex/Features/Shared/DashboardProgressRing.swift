import SwiftUI

struct DashboardProgressRing: View {
    let progress: Double
    let color: Color
    let label: String
    let valueText: String
    var size: CGFloat = DashboardTokens.Spacing.ringSize
    var lineWidth: CGFloat = 4
    var expandHorizontally = true

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                .padding(lineWidth / 2)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)

            VStack(spacing: 1) {
                Text(valueText)
                    .font(DashboardTokens.Font.ringLabel())
                    .foregroundStyle(DashboardTokens.textPrimary)
                Text(label)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .textCase(.uppercase)
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: expandHorizontally ? .infinity : nil, alignment: .center)
        .animation(.easeInOut(duration: 0.4), value: clampedProgress)
    }
}
