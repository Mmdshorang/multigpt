import AppKit

/// Renders a dynamic menu bar icon showing current account usage.
enum MenuBarIconRenderer {
    private static let size = NSSize(width: 18, height: 18)
    private static let scale: CGFloat = 2

    static func render(fiveHourPercent: Double?, weeklyPercent: Double?, isStale: Bool) -> NSImage {
        let canvasSize = NSSize(width: size.width * scale, height: size.height * scale)

        let image = NSImage(size: canvasSize)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return NSImage(systemSymbolName: "gauge.open.with.lines.needle.33percent", accessibilityDescription: nil)!
        }

        let alpha: CGFloat = isStale ? 0.4 : 1.0

        // Background
        context.setFillColor(NSColor.quaternaryLabelColor.withAlphaComponent(alpha * 0.3).cgColor)
        context.fill(CGRect(origin: .zero, size: canvasSize))

        // Top bar (5h window)
        let topBarRect = CGRect(x: 4, y: canvasSize.height - 14, width: canvasSize.width - 8, height: 8)
        drawBar(in: topBarRect, usedPercent: fiveHourPercent, context: context, alpha: alpha)

        // Bottom bar (weekly window)
        let bottomBarRect = CGRect(x: 4, y: 4, width: canvasSize.width - 8, height: 4)
        drawBar(in: bottomBarRect, usedPercent: weeklyPercent, context: context, alpha: alpha)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawBar(in rect: CGRect, usedPercent: Double?, context: CGContext, alpha: CGFloat) {
        context.setFillColor(NSColor.tertiaryLabelColor.withAlphaComponent(alpha * 0.5).cgColor)
        context.fill(rect)

        guard let used = usedPercent, used > 0 else { return }

        let fraction = min(1, max(0, used / 100))
        let fillWidth = rect.width * CGFloat(fraction)
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)

        let color: NSColor
        if used >= 95 {
            color = NSColor.systemRed
        } else if used >= 80 {
            color = NSColor.systemOrange
        } else if used >= 60 {
            color = NSColor.systemYellow
        } else {
            color = NSColor.systemGreen
        }

        context.setFillColor(color.withAlphaComponent(alpha).cgColor)
        context.fill(fillRect)
    }
}
