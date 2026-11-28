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
        guard let previous,
              previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) else { return 0 }
        return await withCheckedContinuation { continuation in
            previous.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: { options in
                continuation.resume(returning: options)
            })
        }
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
