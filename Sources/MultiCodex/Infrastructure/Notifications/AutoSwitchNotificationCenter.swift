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

final class AutoSwitchNotificationCenter: NSObject, AutoSwitchNotificationSending {
    static let shared = AutoSwitchNotificationCenter()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        self.center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        Task { @MainActor in
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else {
                return
            }
            await requestAuthorizationInternal()
        }
    }

    func requestAuthorization() {
        Task { @MainActor in
            await requestAuthorizationInternal()
        }
    }

    private func requestAuthorizationInternal() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(_ payload: AutoSwitchNotificationPayload) {
        Task { @MainActor in
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                await requestAuthorizationInternal()
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = payload.title
            content.body = payload.reason
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "multicodex.auto-switch.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}

extension AutoSwitchNotificationCenter: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list, .banner, .sound])
    }
}
