import Foundation

/// Stores periodic usage snapshots for historical pace analysis.
/// Retained for 8 weeks. Used to compute run-out probability from historical patterns.
actor UsagePaceStore {
    struct Snapshot: Codable {
        let accountName: String
        let sampledAt: Date
        let fiveHourUsedPercent: Double
        let weeklyUsedPercent: Double
        let fiveHourResetsAt: Date?
        let weeklyResetsAt: Date?
    }

    private static let schemaVersion = 1
    private static let retentionDays: TimeInterval = 56

    private let fileURL: URL
    private var snapshots: [Snapshot] = []
    private var loaded = false

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("MultiCodex", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("pace-snapshots.json")
    }

    func record(
        accountName: String,
        fiveHour: UsageMetric,
        weekly: UsageMetric
    ) {
        ensureLoaded()
        let snapshot = Snapshot(
            accountName: accountName,
            sampledAt: Date(),
            fiveHourUsedPercent: fiveHour.usedPercent ?? 0,
            weeklyUsedPercent: weekly.usedPercent ?? 0,
            fiveHourResetsAt: fiveHour.resetsAt,
            weeklyResetsAt: weekly.resetsAt
        )
        snapshots.append(snapshot)
        trimExpired()
        try? persist()
    }

    func snapshots(for accountName: String, since: Date) -> [Snapshot] {
        ensureLoaded()
        return snapshots.filter { $0.accountName == accountName && $0.sampledAt >= since }
    }

    /// Compute run-out probability for an account's 5h window based on historical data.
    func runOutProbability(
        accountName: String,
        currentUsedPercent: Double,
        windowElapsedFraction: Double,
        now: Date = Date()
    ) -> Double? {
        ensureLoaded()

        let currentBurnRate = windowElapsedFraction > 0
            ? currentUsedPercent / (windowElapsedFraction * 100)
            : 0
        guard currentBurnRate > 0 else { return nil }

        let cutoff = now.addingTimeInterval(-Self.retentionDays * 86400)
        let relevant = snapshots.filter { $0.accountName == accountName && $0.sampledAt >= cutoff }

        guard relevant.count >= 5 else { return nil }

        var similarWindows = 0
        var exhaustedWindows = 0

        for snapshot in relevant where snapshot.fiveHourResetsAt != nil {
            let windowStart = snapshot.fiveHourResetsAt!.addingTimeInterval(-5 * 3600)
            let elapsed = snapshot.sampledAt.timeIntervalSince(windowStart)
            let windowFraction = elapsed / (5 * 3600)

            guard windowFraction > 0.1, windowFraction < 0.9 else { continue }

            let historicalRate = snapshot.fiveHourUsedPercent / (windowFraction * 100)
            if abs(historicalRate - currentBurnRate) / max(currentBurnRate, 0.01) < 0.2 {
                similarWindows += 1
                if snapshot.fiveHourUsedPercent >= 95 {
                    exhaustedWindows += 1
                }
            }
        }

        guard similarWindows >= 3 else { return nil }
        return Double(exhaustedWindows) / Double(similarWindows)
    }

    // MARK: - Private

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let container = try? JSONDecoder().decode(SnapshotContainer.self, from: data)
        self.snapshots = container?.snapshots ?? []
    }

    private func trimExpired() {
        let cutoff = Date().addingTimeInterval(-Self.retentionDays * 86400)
        snapshots.removeAll { $0.sampledAt < cutoff }
    }

    private func persist() throws {
        let container = SnapshotContainer(version: Self.schemaVersion, snapshots: snapshots)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(container)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private struct SnapshotContainer: Codable {
        let version: Int
        let snapshots: [UsagePaceStore.Snapshot]
    }
}
