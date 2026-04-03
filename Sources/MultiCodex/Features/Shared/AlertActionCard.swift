import SwiftUI

struct AlertActionCard: View {
    let alert: MenuAlertState
    var isDisabled: Bool = false
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 8
    var cornerRadius: CGFloat = 10
    var fillOpacity: Double = 0.08
    var borderOpacity: Double = 0.22
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: AccountPresentation.alertSymbol(for: alert.severity))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AccountPresentation.alertColor(for: alert.severity))

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AccountPresentation.alertColor(for: alert.severity))
                Text(alert.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            ActionPillButton(
                title: alert.actionTitle,
                symbol: "arrow.right.circle.fill",
                role: .primary,
                isDisabled: isDisabled,
                action: action
            )
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            AccountPresentation.alertColor(for: alert.severity).opacity(fillOpacity),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AccountPresentation.alertColor(for: alert.severity).opacity(borderOpacity), lineWidth: 1)
        )
    }
}
