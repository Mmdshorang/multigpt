import SwiftUI

struct DashboardProgressRing: View {
    let progress: Double
    let color: Color
    let label: String
    let valueText: String
    var size: CGFloat = DashboardTokens.Spacing.ringSize
    var lineWidth: CGFloat = 4.5
    var expandHorizontally = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.028))
                .padding(lineWidth / 2)

            Circle()
                .stroke(Color.white.opacity(0.085), lineWidth: lineWidth)
                .padding(lineWidth / 2)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.70), color],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)

            VStack(spacing: 1) {
                Text(valueText)
                    .font(DashboardTokens.Font.ringLabel())
                    .foregroundStyle(DashboardTokens.textPrimary)
                    .monospacedDigit()
                Text(label)
                    .font(DashboardTokens.Font.caption())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .tracking(0.6)
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: expandHorizontally ? .infinity : nil, alignment: .center)
        .animation(DashboardTokens.Motion.progress(reduceMotion: reduceMotion), value: clampedProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
    }
}
