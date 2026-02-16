import Foundation

enum UsageFormatter {
    private static let fiveHourWindowMinutes = 300
    private static let weeklyWindowMinutes = 10_080

    static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let resetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let resetMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let isoDateParsers: [ISO8601DateFormatter] = {
        let plain = ISO8601DateFormatter()

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [fractional, plain]
    }()

    static func parseISODate(_ raw: String) -> Date? {
        for parser in isoDateParsers {
            if let date = parser.date(from: raw) {
                return date
            }
        }
        return nil
    }

    static func usageSummary(from snapshot: RateLimitSnapshot?) -> UsageSummary {
        guard let snapshot else {
            return UsageSummary(
                fiveHour: UsageMetric(label: "5h", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil, paceStatus: nil),
                weekly: UsageMetric(label: "weekly", percentText: "-", usedPercent: nil, periodMinutes: nil, resetsAt: nil, paceStatus: nil),
                credits: "-"
            )
        }

        let windows = pickWindows(from: snapshot)

        return UsageSummary(
            fiveHour: makeMetric(label: "5h", window: windows.fiveHour),
            weekly: makeMetric(label: "weekly", window: windows.weekly),
            credits: formatCredits(snapshot.credits)
        )
    }

    static func sourceLabel(from result: LimitsResult?) -> String {
        guard let result else {
            return "-"
        }
        if result.source == "cached", let ageSec = result.ageSec {
            return "cached \(ageSec)s"
        }
        return result.source
    }

    static func resetText(for resetDate: Date?, mode: ResetDisplayMode, now: Date = Date()) -> String {
        guard let resetDate else {
            return "-"
        }

        switch mode {
        case .relative:
            return formatRelativeReset(resetDate, now: now)
        case .absolute:
            return formatAbsoluteReset(resetDate, now: now)
        }
    }

    private static func pickWindows(from snapshot: RateLimitSnapshot) -> (fiveHour: RateLimitWindow?, weekly: RateLimitWindow?) {
        let primary = snapshot.primary
        let secondary = snapshot.secondary

        var fiveHour: RateLimitWindow?
        var weekly: RateLimitWindow?

        if primary?.windowDurationMins == fiveHourWindowMinutes {
            fiveHour = primary
        }
        if secondary?.windowDurationMins == fiveHourWindowMinutes {
            fiveHour = secondary
        }
        if primary?.windowDurationMins == weeklyWindowMinutes {
            weekly = primary
        }
        if secondary?.windowDurationMins == weeklyWindowMinutes {
            weekly = secondary
        }

        if fiveHour == nil, let primary, primary != weekly {
            fiveHour = primary
        }
        if weekly == nil, let secondary, secondary != fiveHour {
            weekly = secondary
        }

        return (fiveHour: fiveHour, weekly: weekly)
    }

    private static func makeMetric(label: String, window: RateLimitWindow?) -> UsageMetric {
        let resetDate: Date?
        if let seconds = window?.resetsAt, seconds > 0 {
            resetDate = Date(timeIntervalSince1970: seconds)
        } else {
            resetDate = nil
        }

        return UsageMetric(
            label: label,
            percentText: formatPercent(window?.usedPercent),
            usedPercent: window?.usedPercent,
            periodMinutes: window?.windowDurationMins,
            resetsAt: resetDate,
            paceStatus: paceStatus(for: window)
        )
    }

    private static func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return "-"
        }

        let rounded = (value * 10.0).rounded() / 10.0
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f%%", rounded)
        }
        return String(format: "%.1f%%", rounded)
    }

    private static func formatRelativeReset(_ resetDate: Date, now: Date) -> String {
        let seconds = resetDate.timeIntervalSince(now)
        if seconds <= 5 * 60 {
            return "Resets soon"
        }

        let relative = relativeDateFormatter.localizedString(for: resetDate, relativeTo: now)
        if relative.lowercased().hasPrefix("in ") {
            return "Resets \(relative)"
        }

        return "Resets in \(relative)"
    }

    private static func formatAbsoluteReset(_ resetDate: Date, now _: Date) -> String {
        let calendar = Calendar.current
        let timeText = resetTimeFormatter.string(from: resetDate)

        if calendar.isDateInToday(resetDate) {
            return "Resets today at \(timeText)"
        }

        if calendar.isDateInTomorrow(resetDate) {
            return "Resets tomorrow at \(timeText)"
        }

        let dayText = resetMonthDayFormatter.string(from: resetDate)
        return "Resets \(dayText) at \(timeText)"
    }

    private static func paceStatus(for window: RateLimitWindow?) -> PaceStatus? {
        guard let window,
              let usedPercent = window.usedPercent,
              let resetsAt = window.resetsAt,
              let durationMins = window.windowDurationMins
        else {
            return nil
        }

        let periodDuration = Double(durationMins) * 60
        guard periodDuration > 0 else {
            return nil
        }

        let now = Date().timeIntervalSince1970
        let periodStart = resetsAt - periodDuration
        let elapsed = now - periodStart

        guard elapsed > 0, now < resetsAt else {
            return nil
        }

        if usedPercent <= 0 {
            return .ahead
        }
        if usedPercent >= 100 {
            return .behind
        }

        let elapsedFraction = elapsed / periodDuration
        if elapsedFraction < 0.05 {
            return nil
        }

        let usageRate = usedPercent / elapsed
        let projected = usageRate * periodDuration

        if projected <= 80 {
            return .ahead
        }
        if projected <= 100 {
            return .onTrack
        }
        return .behind
    }

    private static func formatCredits(_ credits: CreditsSnapshot?) -> String {
        guard let credits else {
            return "-"
        }

        if credits.unlimited == true {
            return "unlimited"
        }
        if credits.hasCredits == false {
            return "none"
        }
        if let balance = credits.balance, !balance.isEmpty {
            return balance
        }
        return "-"
    }
}
