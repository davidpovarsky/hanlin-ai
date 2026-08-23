#if os(iOS)
import Foundation
import UserNotifications

public actor HanlinAppleNotificationService {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) { self.center = center }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    public func schedule(_ notification: HanlinScriptLocalNotification) async throws {
        guard notification.fireDate > Date(), !notification.id.isEmpty else {
            throw HanlinAppleDeviceServiceError.invalidRequest("notification")
        }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.userInfo = notification.userInfo
        content.sound = .default
        let interval = notification.fireDate.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try await center.add(.init(identifier: notification.id, content: content, trigger: trigger))
    }

    public func remove(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
}
#endif
