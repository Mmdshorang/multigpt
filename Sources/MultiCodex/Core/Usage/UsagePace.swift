import Foundation

/// Computes usage burn-rate pace for a quota window.
struct UsagePace: Equatable {
    enum Stage: String, Equatable {
        case onTrack
        case slightlyAhead
        case ahead
        case farAhead
        case slightlyBehind
        case behind
        case farBehind

        var isOnTrack: Bool { self == .onTrack }
        var isAhead: Bool { [.slightlyAhead, .ahead, .farAhead].contains(self) }
        var isBehind: Bool { [.slightlyBehind, .behind, .farBehind].contains(self) }
    }

    let stage: Stage
    let deltaPercent: Double
    let expectedUsedPercent: Double
    let actualUsedPercent: Double
    let etaSeconds: TimeInterval?
    let willLastToReset: Bool
    let runOutProbability: Double?

    static func compute(
        usedPercent: Double?,
        periodMinutes: Int?,
        resetsAt: Date?,
        now: Date = Date(),
        runOutProbability: Double? = nil
    ) -> UsagePace? {
        guard let usedPercent,
              let periodMinutes,
              periodMinutes > 0,
              let resetsAt
        else {
            return nil
        }

        let duration = TimeInterval(periodMinutes) * 60
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0, timeUntilReset <= duration else {
            return nil
        }

        let elapsed = (duration - timeUntilReset).clamped(to: 0...duration)
        let actual = usedPercent.clamped(to: 0...100)
        guard elapsed > 0 || actual == 0 else {
            return nil
        }

        let expected = ((elapsed / duration) * 100).clamped(to: 0...100)
        let delta = actual - expected
        let stage = classifyStage(delta: delta)

        var etaSeconds: TimeInterval?
        var willLastToReset = false
        if elapsed > 0, actual > 0 {
            let burnRate = actual / elapsed
            let secondsToExhaust = max(0, 100 - actual) / burnRate
            if secondsToExhaust >= timeUntilReset {
                willLastToReset = true
            } else {
                etaSeconds = secondsToExhaust
            }
        } else if actual == 0 {
            willLastToReset = true
        }

        return UsagePace(
            stage: stage,
            deltaPercent: delta,
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset,
            runOutProbability: runOutProbability
        )
    }

    private static func classifyStage(delta: Double) -> Stage {
        let magnitude = abs(delta)
        if magnitude <= 2 { return .onTrack }
        if magnitude <= 6 { return delta >= 0 ? .slightlyAhead : .slightlyBehind }
        if magnitude <= 12 { return delta >= 0 ? .ahead : .behind }
        return delta >= 0 ? .farAhead : .farBehind
    }

    var summaryText: String {
        switch stage {
        case .onTrack:
            return "On pace"
        case .slightlyAhead, .ahead, .farAhead:
            return "\(Int(abs(deltaPercent).rounded()))% in deficit"
        case .slightlyBehind, .behind, .farBehind:
            return "\(Int(abs(deltaPercent).rounded()))% in reserve"
        }
    }

    var isOnTrack: Bool { stage.isOnTrack }
    var isAhead: Bool { stage.isAhead }
    var isBehind: Bool { stage.isBehind }

    var etaText: String? {
        if willLastToReset {
            return "Lasts until reset"
        }
        guard let etaSeconds else {
            return nil
        }
        if etaSeconds <= 0 {
            return "Runs out now"
        }
        let hours = Int(etaSeconds) / 3_600
        let minutes = (Int(etaSeconds) % 3_600) / 60
        if hours > 0 {
            return "Runs out in \(hours)h \(minutes)m"
        }
        return "Runs out in \(minutes)m"
    }

    var riskText: String? {
        guard let runOutProbability else {
            return nil
        }
        let percent = Int((runOutProbability.clamped(to: 0...1) * 100).rounded())
        return percent > 0 ? "≈ \(percent)% run-out risk" : nil
    }

    var detailText: String {
        [summaryText, etaText, riskText].compactMap { $0 }.joined(separator: " · ")
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
