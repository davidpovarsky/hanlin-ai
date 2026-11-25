import Foundation
import HanlinScriptExtensions
import OSLog
import UIKit
import UserNotifications

/// Both native products install the same ingress before launch completes.
/// The service extension handles mutable remote alerts; this delegate also
/// handles local/nonmutable notifications delivered to or opened in the Host.
@MainActor
public final class HanlinNotificationApplicationDelegate: NSObject, UIApplicationDelegate {
    private var notificationDelegate: HanlinNotificationCenterDelegate?

    public override init() { super.init() }

    public func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        let delegate = HanlinNotificationCenterDelegate(previous: center.delegate)
        notificationDelegate = delegate
        center.delegate = delegate
        return true
    }
}

/// Native callbacks may arrive outside the main actor. Decode the immutable
/// event first; only its Sendable value crosses into the owning Host.
private final class HanlinNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    private static let logger = Logger(subsystem: "com.hanlin.ai", category: "NotificationIngress")
    private let previous: (any UNUserNotificationCenterDelegate)?

    init(previous: (any UNUserNotificationCenterDelegate)?) {
        self.previous = previous
        super.init()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> Int {
        await receive(notification.request.content.userInfo)
        // No original delegate meant no foreground presentation. Preserve that
        // behavior and any installed delegate's actual presentation decision.
        return await previous?.userNotificationCenter?(center, willPresent: notification) ?? 0
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier != UNNotificationDismissActionIdentifier {
            await receive(response.notification.request.content.userInfo)
        }
        await previous?.userNotificationCenter?(center, didReceive: response)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                openSettingsFor notification: UNNotification?) {
        previous?.userNotificationCenter?(center, openSettingsFor: notification)
    }

    private func receive(_ userInfo: [AnyHashable: Any]) async {
        do {
            guard let event = try HanlinNotificationEvent.decode(userInfo: userInfo) else { return }
            try await HanlinScriptingPlatform.shared.receiveNotificationEvent(event)
        } catch {
            // Do not log notification text or fabricate a completed action.
            Self.logger.error("notification_event_not_enqueued")
        }
    }
}
