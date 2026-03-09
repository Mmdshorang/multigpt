import Foundation

enum LoginShellPathResolver {
    static func resolvePath(from environment: [String: String]) -> String? {
        for shell in candidateShells(from: environment) {
            guard let resolved = resolvePath(using: shell, environment: environment) else {
                continue
            }
            let trimmed = resolved.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private static func candidateShells(from environment: [String: String]) -> [String] {
        var shells: [String] = []

        if let configuredShell = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           configuredShell.hasPrefix("/") {
            shells.append(configuredShell)
        }

        shells.append(contentsOf: ["/bin/zsh", "/bin/bash"])

        var seen = Set<String>()
        return shells.filter { seen.insert($0).inserted }
    }

    private static func resolvePath(using shellPath: String, environment: [String: String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            return nil
        }

        return ProcessOutputReader.run(
            executableURL: URL(fileURLWithPath: shellPath),
            arguments: ["-l", "-c", "printf %s \"$PATH\""],
            environment: environment
        )
    }
}
