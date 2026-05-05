import Foundation
import UserNotifications

/// Posts notifications when an account quota window depletes or is restored.
final class QuotaTransitionNotificationCenter {
    static let shared = QuotaTransitionNotificationCenter()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func post(transitions: [QuotaTransitionDetector.WindowTransition]) {
        for transition in transitions where transition.transition != .none {
            postSingle(transition)
        }
    }

    private func postSingle(_ transition: QuotaTransitionDetector.WindowTransition) {
        let title: String
        let body: String
        switch transition.transition {
        case .depleted:
            title = "\(transition.accountName) — \(transition.window.rawValue) depleted"
            body = "Quota is exhausted. MultiCodex will notify you when it recovers."
        case .restored:
            title = "\(transition.accountName) — \(transition.window.rawValue) restored"
            body = "Quota is available again."
        case .none:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = transition.transition == .depleted ? .default : nil

        let request = UNNotificationRequest(
            identifier: "multicodex.quota.\(transition.accountName).\(transition.window.rawValue).\(transition.transition.identifier)",
            content: content,
            trigger: nil
        )

        Task { @MainActor in
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else {
                return
            }
            do {
                try await center.add(request)
                MultiCodexLog.log(
                    .notifications,
                    level: .info,
                    "Posted quota transition notification",
                    metadata: [
                        "account": transition.accountName,
                        "window": transition.window.rawValue,
                        "transition": transition.transition.identifier,
                    ]
                )
            } catch {
                MultiCodexLog.log(
                    .notifications,
                    level: .error,
                    "Failed to post quota transition notification: \(error.localizedDescription)",
                    metadata: ["account": transition.accountName]
                )
            }
        }
    }
}

private extension QuotaTransitionDetector.QuotaTransition {
    var identifier: String {
        switch self {
        case .depleted:
            return "depleted"
        case .restored:
            return "restored"
        case .none:
            return "none"
        }
    }
}
