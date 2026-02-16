import Foundation

struct AccountConfigRecord {
    var currentAccount: String?
    var accounts: Set<String>
}

enum AccountConfigStore {
    static func decodeConfig(from data: Data?) throws -> AccountConfigRecord {
        guard let data, !data.isEmpty else {
            return AccountConfigRecord(currentAccount: nil, accounts: [])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AccountConfigRecord(currentAccount: nil, accounts: [])
        }

        if let version = json["version"] as? Int, (version == 1 || version == 2) {
            let current = json["currentAccount"] as? String
            let accountObjects = json["accounts"] as? [String: Any] ?? [:]
            return AccountConfigRecord(currentAccount: current, accounts: Set(accountObjects.keys))
        }

        return AccountConfigRecord(currentAccount: nil, accounts: [])
    }

    static func encodeConfig(_ config: AccountConfigRecord) throws -> Data {
        let accountsObject = Dictionary(uniqueKeysWithValues: config.accounts.sorted().map { ($0, [String: Any]()) })
        var root: [String: Any] = [
            "version": 2,
            "accounts": accountsObject,
        ]
        if let current = config.currentAccount {
            root["currentAccount"] = current
        }

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
