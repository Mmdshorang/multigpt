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

    private var glowColor: Color {
        if clampedProgress > 0.80 {
            return DashboardTokens.ringGlowCritical
        }
        if clampedProgress > 0.60 {
            return DashboardTokens.ringGlowWarning
        }
        return DashboardTokens.ringGlow
    }

    var body: some View {
        ZStack {
            // Subtle inner fill
            Circle()
                .fill(Color.white.opacity(0.024))
                .padding(lineWidth / 2)

            // Track ring
            Circle()
                .stroke(Color.white.opacity(0.072), lineWidth: lineWidth)
                .padding(lineWidth / 2)

            // Glow layer behind progress arc
            if clampedProgress > 0 {
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.0), color.opacity(0.50)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth + 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
                    .blur(radius: 4)
                    .opacity(0.60)
            }

            // Progress arc
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

            // Cap dot at progress endpoint for visual finish
            if clampedProgress > 0.02, clampedProgress < 0.98 {
                Circle()
                    .fill(color)
                    .frame(width: lineWidth, height: lineWidth)
                    .offset(y: -(size - lineWidth) / 2)
                    .rotationEffect(.degrees(360 * clampedProgress - 90))
                    .shadow(color: color.opacity(0.50), radius: 3, y: 0)
            }

            // Center labels
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
