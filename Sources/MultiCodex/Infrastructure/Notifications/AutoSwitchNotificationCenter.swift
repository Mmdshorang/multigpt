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

enum AutoSwitchNotificationSendResult: Equatable {
    case delivered
    case permissionDenied
    case notAuthorized
    case failed
}

protocol AutoSwitchNotificationSending: AnyObject {
    func requestAuthorizationIfNeeded()
    func requestAuthorization(completion: ((Bool) -> Void)?)
    func send(_ payload: AutoSwitchNotificationPayload, completion: ((AutoSwitchNotificationSendResult) -> Void)?)
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
            guard await currentAuthorizationStatus() == .notDetermined else {
                return
            }
            _ = await requestAuthorizationInternal()
        }
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        Task { @MainActor in
            let granted = await requestAuthorizationInternal()
            completion?(granted)
        }
    }

    private func requestAuthorizationInternal() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func send(_ payload: AutoSwitchNotificationPayload, completion: ((AutoSwitchNotificationSendResult) -> Void)? = nil) {
        Task { @MainActor in
            guard await ensureAuthorizedForDelivery() else {
                let status = await currentAuthorizationStatus()
                if status == .denied {
                    completion?(.permissionDenied)
                } else {
                    completion?(.notAuthorized)
                }
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
            do {
                try await center.add(request)
                completion?(.delivered)
            } catch {
                completion?(.failed)
            }
        }
    }

    private func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private func ensureAuthorizedForDelivery() async -> Bool {
        let status = await currentAuthorizationStatus()
        if status == .notDetermined {
            _ = await requestAuthorizationInternal()
            return isAuthorized(await currentAuthorizationStatus())
        }
        return isAuthorized(status)
    }

    private func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
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
