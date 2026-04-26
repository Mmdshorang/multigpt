import SwiftUI

struct SettingsPanelCard<Content: View>: View {
    @ViewBuilder let content: Content
    var padding: CGFloat = DashboardTokens.Spacing.cardPadding
    var fill: Color = DashboardTokens.cardBackgroundElevated

    init(
        padding: CGFloat = DashboardTokens.Spacing.cardPadding,
        fill: Color = DashboardTokens.cardBackgroundElevated,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: padding, fill: fill, border: DashboardTokens.cardBorder)
    }
}
