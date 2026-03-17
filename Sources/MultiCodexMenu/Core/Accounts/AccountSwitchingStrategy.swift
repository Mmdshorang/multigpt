import Foundation

enum AccountSwitchingStrategy: String, CaseIterable, Identifiable {
    case manual
    case failover
    case expiryAware

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "Manual"
        case .failover:
            return "Failover"
        case .expiryAware:
            return "Expiry-Aware"
        }
    }

    var descriptionText: String {
        switch self {
        case .manual:
            return "Never switch automatically. You choose when to move between accounts."
        case .failover:
            return "Only switch when the current account needs login, errors, or is effectively out of budget."
        case .expiryAware:
            return "Recommended. Prefer accounts whose 5h or weekly headroom is most likely to expire unused."
        }
    }
}
