import Foundation

enum ExecutableSearchPath {
    static let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func merge(_ pathGroups: [String?]) -> String {
        var mergedComponents: [String] = []
        var seen = Set<String>()

        for group in pathGroups {
            for component in components(from: group) where seen.insert(component).inserted {
                mergedComponents.append(component)
            }
        }

        return mergedComponents.joined(separator: ":")
    }

    static func components(from pathValue: String?) -> [String] {
        guard let pathValue else {
            return []
        }

        return pathValue
            .split(separator: ":")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func environment(from environment: [String: String]) -> [String: String] {
        var adjusted = environment
        if adjusted["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            adjusted["PATH"] = fallback
        }
        return adjusted
    }
}
