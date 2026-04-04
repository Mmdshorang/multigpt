import Foundation

struct LimitsCacheRecord<T: Codable>: Codable {
    var version: Int
    var accounts: [String: T]
}

enum LimitsCacheStore {
    static func decode<T: Codable>(
        data: Data?,
        decoder: JSONDecoder,
        defaultVersion: Int
    ) -> LimitsCacheRecord<T> {
        guard let data, !data.isEmpty else {
            return LimitsCacheRecord(version: defaultVersion, accounts: [:])
        }
        if let decoded = try? decoder.decode(LimitsCacheRecord<T>.self, from: data), decoded.version == defaultVersion {
            return decoded
        }
        return LimitsCacheRecord(version: defaultVersion, accounts: [:])
    }

    static func encode<T: Codable>(
        _ cache: LimitsCacheRecord<T>,
        encoder: JSONEncoder
    ) throws -> Data {
        try encoder.encode(cache)
    }
}
