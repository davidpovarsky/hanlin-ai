import Foundation
import UIKit
import UserNotifications

final class NotificationSignatureProbe: NSObject, UNUserNotificationCenterDelegate {
    private let previous: (any UNUserNotificationCenterDelegate)?
    init(previous: (any UNUserNotificationCenterDelegate)?) {
        self.previous = previous
        super.init()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> Int {
        return await previous?.userNotificationCenter?(center, willPresent: notification) ?? 0
    }
}

let notificationSelector = #selector(NotificationSignatureProbe.userNotificationCenter(_:willPresent:))
