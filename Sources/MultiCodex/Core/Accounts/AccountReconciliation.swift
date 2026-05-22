import Foundation

/// Detects and reconciles discrepancies between our stored "current account"
/// and the actual live system auth.
enum AccountReconciliation {
    struct ReconciliationResult: Equatable {
        let configCurrentAccount: String?
        let detectedAccountName: String?
        let detectedEmail: String?
        let isAmbiguous: Bool
        let isInSync: Bool
        let systemAuthChangedExternally: Bool
    }

    static func reconcile(
        configCurrentAccount: String?,
        systemAuthLastModified: Date?,
        knownAccountLastModified: Date?,
        systemIdentity: ResolvedAccountIdentity?,
        accountIdentities: [String: AccountIdentity]
    ) -> ReconciliationResult {
        var detectedAccountName: String?
        var matchingAccountCount = 0

        if let systemID = systemIdentity {
            let detectedIdentity: AccountIdentity
            if let providerID = systemID.accountId, !providerID.isEmpty {
                detectedIdentity = .providerAccount(id: providerID)
            } else if let email = systemID.email {
                detectedIdentity = .emailOnly(normalizedEmail: email.lowercased())
            } else {
                detectedIdentity = .unresolved
            }

            if detectedIdentity != .unresolved {
                var matches: [String] = []
                for name in accountIdentities.keys.sorted() {
                    if let knownIdentity = accountIdentities[name],
                       AccountIdentityMatcher.matches(detectedIdentity, knownIdentity)
                    {
                        matches.append(name)
                    }
                }
                matchingAccountCount = matches.count
                if matches.count == 1 {
                    detectedAccountName = matches[0]
                }
            }
        }

        let isAmbiguous = matchingAccountCount > 1

        let externallyModified: Bool
        if let systemModified = systemAuthLastModified,
           let knownModified = knownAccountLastModified
        {
            externallyModified = systemModified > knownModified.addingTimeInterval(5)
        } else {
            externallyModified = false
        }

        let isInSync: Bool
        if isAmbiguous {
            isInSync = false
        } else if let configName = configCurrentAccount, let detected = detectedAccountName {
            isInSync = configName == detected
        } else if configCurrentAccount == nil, detectedAccountName == nil {
            isInSync = true
        } else {
            isInSync = false
        }

        return ReconciliationResult(
            configCurrentAccount: configCurrentAccount,
            detectedAccountName: detectedAccountName,
            detectedEmail: systemIdentity?.email,
            isAmbiguous: isAmbiguous,
            isInSync: isInSync,
            systemAuthChangedExternally: externallyModified
        )
    }
}
