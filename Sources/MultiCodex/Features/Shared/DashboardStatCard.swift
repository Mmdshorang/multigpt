import SwiftUI

struct DashboardSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(DashboardTokens.textTertiary)
    }
}

struct DashboardStatCard: View {
    let label: String
    let value: String
    var sublabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DashboardSectionHeader(title: label)

            Text(value)
                .font(DashboardTokens.Font.cardHeading())
                .foregroundStyle(DashboardTokens.textPrimary)
                .lineLimit(1)

            if let sublabel {
                Text(sublabel)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DashboardTokens.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .fill(DashboardTokens.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTokens.Spacing.cardRadius, style: .continuous)
                .stroke(DashboardTokens.cardBorder, lineWidth: 1)
        )
    }
}
