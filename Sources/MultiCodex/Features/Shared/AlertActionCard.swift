import SwiftUI

struct AlertActionCard: View {
    let alert: MenuAlertState
    var isDisabled: Bool = false
    var horizontalPadding: CGFloat = DashboardTokens.Spacing.cardPadding
    var verticalPadding: CGFloat = 10
    var cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius
    var fillOpacity: Double = 0.08
    var borderOpacity: Double = 0.22
    let action: () -> Void
    let secondaryAction: (() -> Void)?

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
        case .externalAuth:
            return "Import"
        }
    }

    private var actionRole: ActionPillRole {
        alert.severity == .refreshError ? .primary : .secondary
    }

    init(
        alert: MenuAlertState,
        isDisabled: Bool = false,
        horizontalPadding: CGFloat = DashboardTokens.Spacing.cardPadding,
        verticalPadding: CGFloat = 10,
        cornerRadius: CGFloat = DashboardTokens.Spacing.cardRadius,
        fillOpacity: Double = 0.08,
        borderOpacity: Double = 0.22,
        action: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.alert = alert
        self.isDisabled = isDisabled
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.cornerRadius = cornerRadius
        self.fillOpacity = fillOpacity
        self.borderOpacity = borderOpacity
        self.action = action
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tone.opacity(0.14))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: AccountPresentation.alertSymbol(for: alert.severity))
                        .font(DashboardTokens.Font.bodySemibold())
                        .foregroundStyle(tone)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(severityLabel.uppercased())
                        .font(DashboardTokens.Font.caption())
                        .tracking(0.6)
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

            HStack(spacing: 6) {
                if let secondaryAction, let title = alert.secondaryActionTitle {
                    ActionPillButton(
                        title: title,
                        symbol: "exclamationmark.triangle.fill",
                        role: .secondary,
                        isDisabled: isDisabled,
                        action: secondaryAction
                    )
                }
                ActionPillButton(
                    title: alert.actionTitle,
                    symbol: "arrow.right.circle.fill",
                    role: actionRole,
                    isDisabled: isDisabled,
                    action: action
                )
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            tone.opacity(fillOpacity),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(tone.opacity(borderOpacity), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }
}
