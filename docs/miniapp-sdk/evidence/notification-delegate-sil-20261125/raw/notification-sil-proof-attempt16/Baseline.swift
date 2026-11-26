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
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await previous?.userNotificationCenter?(center, didReceive: response)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                openSettingsFor notification: UNNotification?) {
        previous?.userNotificationCenter?(center, openSettingsFor: notification)
    }
}

let notificationSelector = #selector(NotificationSignatureProbe.userNotificationCenter(_:willPresent:))
let responseSelector = #selector(NotificationSignatureProbe.userNotificationCenter(_:didReceive:))
let settingsSelector = #selector(NotificationSignatureProbe.userNotificationCenter(_:openSettingsFor:))
