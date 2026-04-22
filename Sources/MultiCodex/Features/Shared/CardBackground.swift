import SwiftUI

struct CardBackgroundModifier: ViewModifier {
    var padding: CGFloat = DashboardTokens.Spacing.cardPadding
    var cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius
    var fill: Color = DashboardTokens.cardBackground
    var border: Color = DashboardTokens.cardBorder
    var hasShadow = false

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
                    .stroke(border, lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .shadow(
                color: DashboardTokens.shadowColor.opacity(hasShadow ? 0.12 : 0),
                radius: hasShadow ? 8 : 0,
                y: hasShadow ? 4 : 0
            )
    }
}

extension View {
    func cardStyle(
        padding: CGFloat = DashboardTokens.Spacing.cardPadding,
        cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius,
        fill: Color = DashboardTokens.cardBackground,
        border: Color = DashboardTokens.cardBorder,
        hasShadow: Bool = false
    ) -> some View {
        modifier(CardBackgroundModifier(
            padding: padding,
            cornerRadius: cornerRadius,
            fill: fill,
            border: border,
            hasShadow: hasShadow
        ))
    }
}
