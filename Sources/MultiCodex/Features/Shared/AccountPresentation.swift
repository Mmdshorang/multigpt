import SwiftUI

struct RuntimeStatusPresentation {
    let text: String
    let symbol: String
    let color: Color
}

enum AccountPresentation {
    static func statusColor(for state: AccountConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .needsLogin:
            return .orange
        case .error:
            return .red
        }
    }

    static func alertColor(for severity: MenuAlertState.Severity) -> Color {
        switch severity {
        case .runtimeUnavailable:
            return .orange
        case .refreshError:
            return .red
        case .authRequired:
            return .orange
        }
    }

    static func alertSymbol(for severity: MenuAlertState.Severity) -> String {
        switch severity {
        case .runtimeUnavailable:
            return "terminal"
        case .refreshError:
            return "exclamationmark.triangle.fill"
        case .authRequired:
            return "person.crop.circle.badge.exclamationmark"
        }
    }

    static func runtimeStatus(summary: String?, isAvailable: Bool) -> RuntimeStatusPresentation {
        if isAvailable {
            return RuntimeStatusPresentation(
                text: summary ?? "codex runtime is available.",
                symbol: "checkmark.circle.fill",
                color: .green
            )
        }

        if let summary {
            return RuntimeStatusPresentation(
                text: summary,
                symbol: "exclamationmark.triangle.fill",
                color: .orange
            )
        }

        return RuntimeStatusPresentation(
            text: "Checking codex runtime...",
            symbol: "clock",
            color: .secondary
        )
    }
}

struct AccountStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

struct SubtleWarningRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct AccountUsageMetricCard: View {
    let title: String
    let metric: UsageMetric
    let resetDisplayMode: ResetDisplayMode
    let progressValue: Double

    private var tone: Color {
        switch UsageLevel.from(usedPercent: metric.usedPercent) {
        case .critical:
            return .red
        case .warning:
            return .orange
        case .normal:
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(metric.percentText)
                    .font(.caption.weight(.semibold))
            }

            ProgressView(value: progressValue)
                .tint(tone)

            Text(metric.resetText(mode: resetDisplayMode))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
