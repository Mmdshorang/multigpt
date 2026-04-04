import Foundation

struct AccountConfigRecord {
    var currentAccount: String?
    var accounts: Set<String>
}

enum AccountConfigStore {
    private struct VersionedConfigRecord: Codable {
        let version: Int
        let currentAccount: String?
        let accounts: [String: EmptyAccountRecord]
    }

    private struct EmptyAccountRecord: Codable {}

    private static let supportedVersion = 2

    static func decodeConfig(from data: Data?) throws -> AccountConfigRecord {
        guard let data, !data.isEmpty else {
            return AccountConfigRecord(currentAccount: nil, accounts: [])
        }

        guard let decoded = try? JSONDecoder().decode(VersionedConfigRecord.self, from: data),
              decoded.version == supportedVersion
        else {
            return AccountConfigRecord(currentAccount: nil, accounts: [])
        }

        return AccountConfigRecord(
            currentAccount: decoded.currentAccount,
            accounts: Set(decoded.accounts.keys)
        )
    }

    static func encodeConfig(_ config: AccountConfigRecord) throws -> Data {
        let accounts = Dictionary(
            uniqueKeysWithValues: config.accounts.sorted().map { ($0, EmptyAccountRecord()) }
        )
        let record = VersionedConfigRecord(
            version: supportedVersion,
            currentAccount: config.currentAccount,
            accounts: accounts
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(record)
    }
}
