import Foundation
import os

/// Centralized logging for MultiCodex.
enum MultiCodexLog {
    enum Category: String {
        case rpc
        case auth
        case switching
        case refresh
        case usage
        case pace
        case cost
        case identity
        case config
        case notifications
    }

    private static let subsystem = "com.multicodex.app"

    static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }

    static func log(
        _ category: Category,
        level: OSLogType = .info,
        _ message: String,
        metadata: [String: String] = [:]
    ) {
        let redactedMessage = LogRedactor.redact(message)
        let redactedMetadata = metadata.mapValues(LogRedactor.redact)
        let logger = Self.logger(category)

        switch level {
        case .debug:
            logger.debug("\(redactedMessage, privacy: .public)")
        case .info:
            logger.info("\(redactedMessage, privacy: .public)")
        case .error:
            logger.error("\(redactedMessage, privacy: .public)")
        case .fault:
            logger.fault("\(redactedMessage, privacy: .public)")
        default:
            logger.log(level: level, "\(redactedMessage, privacy: .public)")
        }

        FileLogHandler.shared.append(
            category: category.rawValue,
            level: level,
            message: redactedMessage,
            metadata: redactedMetadata
        )
    }
}

/// Simple asynchronous file logger with size-based rotation.
final class FileLogHandler {
    static let shared = FileLogHandler()

    private let queue = DispatchQueue(label: "com.multicodex.filelog", qos: .utility)
    private let logFileURL: URL
    private let maxFileSize = 1_024_000

    private init() {
        let logDir = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("MultiCodex", isDirectory: true)

        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        logFileURL = logDir.appendingPathComponent("multicodex.log")
    }

    func append(category: String, level: OSLogType, message: String, metadata: [String: String]) {
        queue.async { [logFileURL, maxFileSize] in
            let line = Self.formatLine(
                category: category,
                level: level,
                message: message,
                metadata: metadata
            )
            guard let data = line.data(using: .utf8) else { return }

            Self.rotateIfNeeded(logFileURL: logFileURL, maxFileSize: maxFileSize)

            if FileManager.default.fileExists(atPath: logFileURL.path),
               let handle = try? FileHandle(forWritingTo: logFileURL)
            {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }

    private static func formatLine(
        category: String,
        level: OSLogType,
        message: String,
        metadata: [String: String]
    ) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let metadataText = metadata.isEmpty
            ? ""
            : " " + metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
        return "[\(timestamp)] [\(level.label)] [\(category)] \(message)\(metadataText)\n"
    }

    private static func rotateIfNeeded(logFileURL: URL, maxFileSize: Int) {
        guard FileManager.default.fileExists(atPath: logFileURL.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attributes[.size] as? Int,
              size > maxFileSize,
              let existing = try? Data(contentsOf: logFileURL)
        else {
            return
        }

        let keepCount = min(existing.count, maxFileSize / 2)
        let suffix = existing.suffix(keepCount)
        if let newlineIndex = suffix.firstIndex(of: 0x0A) {
            try? Data(suffix[suffix.index(after: newlineIndex)...]).write(to: logFileURL, options: .atomic)
        } else {
            try? Data(suffix).write(to: logFileURL, options: .atomic)
        }
    }
}

private extension OSLogType {
    var label: String {
        switch self {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        default:
            return "INFO"
        }
    }
}
