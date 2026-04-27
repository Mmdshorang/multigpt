import Foundation

/// Scans Codex JSONL session log files to extract token usage and compute costs.
enum CostUsageScanner {
    struct SessionEntry {
        let model: String
        let inputTokens: Int
        let cachedInputTokens: Int
        let outputTokens: Int
        let timestamp: Date?
    }

    struct ScanResult {
        let entries: [SessionEntry]
        let totalCostUSD: Double
        let todayCostUSD: Double
        let weekCostUSD: Double
        let byModel: [String: Double]
        let totalInputTokens: Int
        let totalOutputTokens: Int
    }

    /// Scan a directory for JSONL files and aggregate costs.
    static func scan(directory: URL, now: Date = Date()) -> ScanResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            return ScanResult(entries: [], totalCostUSD: 0, todayCostUSD: 0, weekCostUSD: 0, byModel: [:], totalInputTokens: 0, totalOutputTokens: 0)
        }

        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            .map { $0.filter { $0.pathExtension == "jsonl" } } ?? []

        var entries: [SessionEntry] = []
        var totalCost = 0.0
        var todayCost = 0.0
        var weekCost = 0.0
        var byModel: [String: Double] = [:]
        var totalInput = 0
        var totalOutput = 0

        let todayStart = Calendar.current.startOfDay(for: now)
        let weekStart = now.addingTimeInterval(-7 * 86400)

        for file in files {
            guard let data = fm.contents(atPath: file.path),
                  let text = String(data: data, encoding: String.Encoding.utf8)
            else { continue }

            for line in text.split(separator: "\n") {
                guard let lineData = String(line).data(using: String.Encoding.utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }

                let model = json["model"] as? String ?? "unknown"
                let usage = json["usage"] as? [String: Any]

                let inputTokens = (usage?["input_tokens"] as? Int) ?? 0
                let cachedTokens = (usage?["cached_input_tokens"] as? Int)
                    ?? (usage?["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int
                    ?? 0
                let outputTokens = (usage?["output_tokens"] as? Int) ?? 0
                let timestamp = (json["timestamp"] as? String).flatMap(parseDate)

                guard inputTokens > 0 || outputTokens > 0 else { continue }

                let entry = SessionEntry(
                    model: model,
                    inputTokens: inputTokens,
                    cachedInputTokens: cachedTokens,
                    outputTokens: outputTokens,
                    timestamp: timestamp
                )
                entries.append(entry)

                if let cost = CostPricing.costUSD(
                    model: model,
                    inputTokens: inputTokens,
                    cachedInputTokens: cachedTokens,
                    outputTokens: outputTokens
                ) {
                    totalCost += cost
                    byModel[model, default: 0] += cost

                    if let ts = timestamp {
                        if ts >= todayStart { todayCost += cost }
                        if ts >= weekStart { weekCost += cost }
                    }
                }

                totalInput += inputTokens
                totalOutput += outputTokens
            }
        }

        return ScanResult(
            entries: entries,
            totalCostUSD: totalCost,
            todayCostUSD: todayCost,
            weekCostUSD: weekCost,
            byModel: byModel,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput
        )
    }

    /// Build a CostReport from a scan result.
    static func report(for accountName: String, from result: ScanResult, now: Date = Date()) -> CostReport {
        CostReport(
            accountName: accountName,
            totalCostUSD: result.totalCostUSD,
            todayCostUSD: result.todayCostUSD,
            weekCostUSD: result.weekCostUSD,
            byModel: result.byModel,
            totalInputTokens: result.totalInputTokens,
            totalOutputTokens: result.totalOutputTokens,
            sampledAt: now
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f2.date(from: raw) ?? f1.date(from: raw)
    }
}
