import SwiftUI

struct ProfileUsageCardView: View {
    let profile: ProfileUsage
    let resetDisplayMode: ResetDisplayMode
    let isSwitching: Bool
    let isRunningAuthAction: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let onSwitch: () -> Void
    let onRelogin: () -> Void
    let onToggleExpanded: () -> Void

    private enum PrimaryAction {
        case switchProfile
        case relogin
    }

    private var isBusy: Bool {
        isSwitching || isRunningAuthAction
    }

    private var primaryAction: PrimaryAction? {
        if profile.connectionState == .needsLogin {
            return .relogin
        }
        if !profile.isCurrent {
            return .switchProfile
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rowTop
            rowUsage

            if isExpanded {
                expandedDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardBorderColor, lineWidth: isSelected ? 1.4 : 1)
        )
    }

    private var rowTop: some View {
        HStack(spacing: 8) {
            Text(profile.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if profile.isCurrent {
                statePill("Current", tone: .accentColor)
            }

            statePill(profile.connectionState.label, tone: statusTone)

            Spacer(minLength: 8)

            if let primaryAction {
                switch primaryAction {
                case .switchProfile:
                    Button {
                        onSwitch()
                    } label: {
                        if isSwitching {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Switch")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isBusy)
                case .relogin:
                    Button {
                        onRelogin()
                    } label: {
                        if isRunningAuthAction {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Re-login")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isBusy)
                }
            }

            Button {
                onToggleExpanded()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide details" : "Show details")
        }
    }

    private var rowUsage: some View {
        HStack(spacing: 8) {
            MinimalMetricView(metric: profile.usage.fiveHour, title: "5h", resetDisplayMode: resetDisplayMode, showReset: isExpanded)
            MinimalMetricView(metric: profile.usage.weekly, title: "weekly", resetDisplayMode: resetDisplayMode, showReset: isExpanded)
        }
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let hint = profile.connectionHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(statusTone)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Text(profile.source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Last used \(profile.lastUsedLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)

            if let status = profile.lastLoginStatusPreview {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.top, 2)
    }

    private var statusTone: Color {
        switch profile.connectionState {
        case .connected:
            return .green
        case .needsLogin:
            return .orange
        case .error:
            return .red
        }
    }

    private var cardBorderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.55)
        }
        if profile.connectionState == .error {
            return Color.red.opacity(0.24)
        }
        if profile.connectionState == .needsLogin {
            return Color.orange.opacity(0.24)
        }
        if profile.isCurrent {
            return Color.accentColor.opacity(0.26)
        }
        return Color.secondary.opacity(0.14)
    }

    private func statePill(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tone.opacity(0.13), in: Capsule())
            .foregroundStyle(tone)
    }
}

private struct MinimalMetricView: View {
    let metric: UsageMetric
    let title: String
    let resetDisplayMode: ResetDisplayMode
    let showReset: Bool

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

            ProgressView(value: metric.normalizedFraction)
                .tint(tone)

            if showReset {
                Text(metric.resetText(mode: resetDisplayMode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
