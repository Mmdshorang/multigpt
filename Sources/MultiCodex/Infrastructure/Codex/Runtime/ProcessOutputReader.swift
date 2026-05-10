import Foundation

enum ProcessOutputReader {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) -> String? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read pipe data BEFORE waitUntilExit to avoid pipe buffer deadlock.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        _ = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}
