import Foundation

/// Strips personally identifying or sensitive values before messages are written to logs.
enum LogRedactor {
    private static let emailRegex = makeRegex(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
        options: [.caseInsensitive]
    )
    private static let bearerRegex = makeRegex(
        pattern: #"(?i)\bbearer\s+[a-z0-9._\-]+=*\b"#
    )
    private static let accessTokenRegex = makeRegex(
        pattern: #"(?i)(access_token[\"\s:=]+)[\"a-z0-9_\-\.]{20,}"#
    )
    private static let refreshTokenRegex = makeRegex(
        pattern: #"(?i)(refresh_token[\"\s:=]+)[\"a-z0-9_\-\.]{20,}"#
    )
    private static let idTokenRegex = makeRegex(
        pattern: #"(?i)(id_token[\"\s:=]+)[\"a-z0-9_\-\.]{20,}"#
    )

    static func redact(_ text: String) -> String {
        var output = text
        output = replace(emailRegex, in: output, with: "<email>")
        output = replace(bearerRegex, in: output, with: "Bearer <token>")
        output = replace(accessTokenRegex, in: output, with: "$1<token>")
        output = replace(refreshTokenRegex, in: output, with: "$1<token>")
        output = replace(idTokenRegex, in: output, with: "$1<token>")
        return output
    }

    private static func makeRegex(
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
            return regex
        }
        return try! NSRegularExpression(pattern: "$^", options: [])
    }

    private static func replace(
        _ regex: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}
