import Foundation

enum RateLimitsRPCClient {
    static func writeMessage(_ payload: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        handle.write(data)
        if let newline = "\n".data(using: .utf8) {
            handle.write(newline)
        }
    }
}
