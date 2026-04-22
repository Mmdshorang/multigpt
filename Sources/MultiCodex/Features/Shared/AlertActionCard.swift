import SwiftUI

struct AlertActionCard: View {
    let alert: MenuAlertState
    var isDisabled: Bool = false
    var horizontalPadding: CGFloat = DashboardTokens.Spacing.cardPadding
    var verticalPadding: CGFloat = DashboardTokens.scaled(10)
    var cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius
    var fillOpacity: Double = 0.10
    var borderOpacity: Double = 0.25
    let action: () -> Void

    private var tone: Color {
        AccountPresentation.alertColor(for: alert.severity)
    }

    private var severityLabel: String {
        switch alert.severity {
        case .runtimeUnavailable:
            return "Runtime"
        case .refreshError:
            return "Error"
        case .authRequired:
            return "Account"
        }
    }

    private var actionRole: ActionPillRole {
        alert.severity == .refreshError ? .primary : .secondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: DashboardTokens.scaled(10)) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tone.opacity(0.16))
                .frame(width: DashboardTokens.scaled(28), height: DashboardTokens.scaled(28))
                .overlay(
                    Image(systemName: AccountPresentation.alertSymbol(for: alert.severity))
                        .font(.system(size: DashboardTokens.scaled(12), weight: .semibold))
                        .foregroundStyle(tone)
                )

            VStack(alignment: .leading, spacing: DashboardTokens.scaled(4)) {
                HStack(spacing: DashboardTokens.scaled(6)) {
                    Text(severityLabel.uppercased())
                        .font(.system(size: DashboardTokens.scaled(9), weight: .semibold))
                        .tracking(0.9)
                        .foregroundStyle(tone)
                    Text(alert.title)
                        .font(DashboardTokens.Font.metadata().weight(.semibold))
                        .foregroundStyle(DashboardTokens.textPrimary)
                }

                Text(alert.message)
                    .font(DashboardTokens.Font.metadata())
                    .foregroundStyle(DashboardTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            ActionPillButton(
                title: alert.actionTitle,
                symbol: "arrow.right.circle.fill",
                role: actionRole,
                isDisabled: isDisabled,
                action: action
            )
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            tone.opacity(fillOpacity),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(tone.opacity(borderOpacity), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
