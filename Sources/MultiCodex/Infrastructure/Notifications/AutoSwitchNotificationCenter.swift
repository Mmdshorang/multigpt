import Foundation
import UserNotifications

struct AutoSwitchNotificationPayload: Equatable {
    let previousAccountName: String?
    let newAccountName: String
    let reason: String

    var title: String {
        let previous = previousAccountName ?? "None"
        return "Auto-switched: \(previous) -> \(newAccountName)"
    }
}

protocol AutoSwitchNotificationSending: AnyObject {
    func requestAuthorizationIfNeeded()
    func requestAuthorization()
    func send(_ payload: AutoSwitchNotificationPayload)
}

final class AutoSwitchNotificationCenter: AutoSwitchNotificationSending {
    static let shared = AutoSwitchNotificationCenter()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else {
                return
            }
            await requestAuthorizationInternal()
        }
    }

    func requestAuthorization() {
        Task {
            await requestAuthorizationInternal()
        }
    }

    private func requestAuthorizationInternal() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(_ payload: AutoSwitchNotificationPayload) {
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = payload.title
            content.body = payload.reason
            content.sound = nil
            if #available(macOS 12.0, *) {
                content.interruptionLevel = .passive
            }

            let request = UNNotificationRequest(
                identifier: "multicodex.auto-switch.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}
