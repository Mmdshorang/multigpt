import SwiftUI

extension SettingsContentView {
    var settingsContentMaxWidth: CGFloat { 900 }

    var settingsBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }

    func settingsSectionIntro(
        title: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func settingsInsetPanel<Content: View>(
        title: String? = nil,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func settingsFormRow<Control: View>(
        _ label: String,
        detail: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.semibold))

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            control()
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
