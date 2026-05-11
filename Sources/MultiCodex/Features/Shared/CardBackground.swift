import SwiftUI

struct CardBackgroundModifier: ViewModifier {
    var padding: CGFloat = DashboardTokens.Spacing.cardPadding
    var cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius
    var fill: Color = DashboardTokens.cardBackground
    var border: Color = DashboardTokens.cardBorder
    var hasShadow = false
    var hasGlass = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)

                    if hasGlass {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(DashboardTokens.glassHighlight)
                    }
                }
                .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 0.5)
                    .allowsHitTesting(false)
            )
            .shadow(
                color: hasShadow ? DashboardTokens.shadowSubtle : .clear,
                radius: hasShadow ? 12 : 0,
                y: hasShadow ? 6 : 0
            )
            .shadow(
                color: hasShadow ? DashboardTokens.shadowMedium : .clear,
                radius: hasShadow ? 2 : 0,
                y: hasShadow ? 1 : 0
            )
    }
}

extension View {
    func cardStyle(
        padding: CGFloat = DashboardTokens.Spacing.cardPadding,
        cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius,
        fill: Color = DashboardTokens.cardBackground,
        border: Color = DashboardTokens.cardBorder,
        hasShadow: Bool = false,
        hasGlass: Bool = false
    ) -> some View {
        modifier(CardBackgroundModifier(
            padding: padding,
            cornerRadius: cornerRadius,
            fill: fill,
            border: border,
            hasShadow: hasShadow,
            hasGlass: hasGlass
        ))
    }
}
