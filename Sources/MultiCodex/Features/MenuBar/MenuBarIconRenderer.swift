import AppKit

/// Renders a dynamic menu bar icon showing current account usage.
enum MenuBarIconRenderer {
    private static let size = NSSize(width: 18, height: 18)

    static func render(fiveHourPercent: Double?, weeklyPercent: Double?, isStale: Bool) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return fallbackIcon()
        }

        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        let alpha: CGFloat = isStale ? 0.48 : 1
        let fiveHour = normalized(fiveHourPercent)
        let weekly = normalized(weeklyPercent)

        drawUsageBar(
            in: CGRect(x: 2.5, y: 10.5, width: 13, height: 3.5),
            progress: fiveHour,
            accent: color(for: fiveHourPercent),
            alpha: alpha,
            context: context
        )
        drawUsageBar(
            in: CGRect(x: 2.5, y: 4.5, width: 13, height: 3.5),
            progress: weekly,
            accent: color(for: weeklyPercent),
            alpha: alpha,
            context: context
        )

        if isStale {
            context.setFillColor(NSColor.systemOrange.withAlphaComponent(0.95).cgColor)
            context.fillEllipse(in: CGRect(x: 13, y: 13, width: 3, height: 3))
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawUsageBar(
        in rect: CGRect,
        progress: CGFloat,
        accent: NSColor,
        alpha: CGFloat,
        context: CGContext
    ) {
        let radius = rect.height / 2
        let track = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(track)
        context.setFillColor(NSColor.labelColor.withAlphaComponent(alpha * 0.18).cgColor)
        context.fillPath()

        guard progress > 0 else { return }

        let fillRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: max(rect.height, rect.width * progress),
            height: rect.height
        )
        let fill = CGPath(roundedRect: fillRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.addPath(fill)
        context.setFillColor(accent.withAlphaComponent(alpha).cgColor)
        context.fillPath()
    }

    private static func normalized(_ percent: Double?) -> CGFloat {
        guard let percent else { return 0 }
        return CGFloat(min(1, max(0, percent / 100)))
    }

    private static func color(for percent: Double?) -> NSColor {
        guard let percent else {
            return NSColor.systemGray
        }
        if percent >= 95 { return NSColor.systemRed }
        if percent >= 80 { return NSColor.systemOrange }
        return NSColor.systemPurple
    }

    private static func fallbackIcon() -> NSImage {
        let image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "MultiCodex")
            ?? NSImage(size: size)
        image.size = size
        image.isTemplate = true
        return image
    }
}
