import SwiftUI

struct DashboardSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(DashboardTokens.Font.sectionLabel())
            .tracking(1.1)
            .foregroundStyle(DashboardTokens.textTertiary)
    }
}

struct DashboardStatCard: View {
    let label: String
    let value: String
    var sublabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTokens.scaled(8)) {
            DashboardSectionHeader(title: label)

            Text(value)
                .font(DashboardTokens.Font.statValue())
                .foregroundStyle(DashboardTokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let sublabel {
                Text(sublabel)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: DashboardTokens.scaled(92), alignment: .leading)
        .cardStyle(padding: DashboardTokens.Spacing.compactCardPadding, fill: DashboardTokens.cardBackgroundSubtle)
    }
}
