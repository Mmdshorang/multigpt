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
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
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
