import SwiftUI

struct CardBackgroundModifier: ViewModifier {
    var padding: CGFloat = DashboardTokens.Spacing.cardPadding
    var cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius
    var fill: Color = DashboardTokens.cardBackground
    var border: Color = DashboardTokens.cardBorder

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(DashboardTokens.cardHighlightGradient.opacity(0.45))
                    .blendMode(.screen)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(color: DashboardTokens.shadowColor.opacity(0.18), radius: 18, y: 10)
    }
}

extension View {
    func cardStyle(
        padding: CGFloat = DashboardTokens.Spacing.cardPadding,
        cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius,
        fill: Color = DashboardTokens.cardBackground,
        border: Color = DashboardTokens.cardBorder
    ) -> some View {
        modifier(CardBackgroundModifier(
            padding: padding,
            cornerRadius: cornerRadius,
            fill: fill,
            border: border
        ))
    }
}
