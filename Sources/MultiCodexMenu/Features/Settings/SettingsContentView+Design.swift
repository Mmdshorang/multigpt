import SwiftUI

extension SettingsContentView {
    var settingsContentMaxWidth: CGFloat { 960 }

    var settingsBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.accentColor.opacity(0.035),
                Color(nsColor: .underPageBackgroundColor),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    func settingsSectionIntro(
        eyebrow: String,
        title: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func settingsMetricTile(
        title: String,
        value: String,
        detail: String,
        tint: Color = .accentColor
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.11),
                            Color(nsColor: .controlBackgroundColor).opacity(0.92),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }

    func settingsInsetPanel<Content: View>(
        title: String? = nil,
        description: String? = nil,
        tint: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        )
    }

    func settingsFormRow<Control: View>(
        _ label: String,
        detail: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))

                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)

                control()
                    .frame(maxWidth: 260, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func settingsInfoRow(symbol: String, text: String, color: Color = .secondary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
