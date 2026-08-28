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
        guard !notification.id.isEmpty, !notification.title.isEmpty else {
            throw HanlinAppleDeviceServiceError.invalidRequest("notification")
        }
        guard try await requestAuthorization() else {
            throw HanlinAppleDeviceServiceError.denied(.notifications)
        }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        content.badge = notification.badge.map(NSNumber.init(value:))
        content.threadIdentifier = notification.threadIdentifier
        content.sound = notification.silent ? nil : .default
        content.interruptionLevel = switch notification.interruptionLevel {
        case "passive": .passive
        case "timeSensitive": .timeSensitive
        default: .active
        }
        if let data = notification.userInfoJSON,
           let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            content.userInfo = object
        }
        let trigger: UNNotificationTrigger? = switch notification.trigger {
        case .immediate:
            nil
        case let .timeInterval(seconds, repeats):
            UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: repeats)
        case let .calendar(values, timeZoneIdentifier, repeats):
            UNCalendarNotificationTrigger(
                dateMatching: try Self.dateComponents(values, timeZoneIdentifier: timeZoneIdentifier),
                repeats: repeats
            )
        }
        try await center.add(.init(identifier: notification.id, content: content, trigger: trigger))
    }

    public func remove(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }

    public func removePending(identifierPrefix: String) async {
        let requests = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: requests.lazy.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        )
    }

    private static func dateComponents(
        _ values: [String: Int],
        timeZoneIdentifier: String?
    ) throws -> DateComponents {
        var components = DateComponents()
        if let timeZoneIdentifier {
            guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
                throw HanlinAppleDeviceServiceError.invalidRequest("notification_time_zone")
            }
            components.timeZone = timeZone
        }
        components.era = values["era"]
        components.year = values["year"]
        components.yearForWeekOfYear = values["yearForWeekOfYear"]
        components.quarter = values["quarter"]
        components.month = values["month"]
        components.weekOfMonth = values["weekOfMonth"]
        components.weekOfYear = values["weekOfYear"]
        components.weekday = values["weekday"]
        components.weekdayOrdinal = values["weekdayOrdinal"]
        components.day = values["day"]
        components.hour = values["hour"]
        components.minute = values["minute"]
        components.second = values["second"]
        components.nanosecond = values["nanosecond"]
        guard Calendar.current.nextDate(
            after: Date(), matching: components, matchingPolicy: .nextTime
        ) != nil else {
            throw HanlinAppleDeviceServiceError.invalidRequest("notification_date_components")
        }
        return components
    }
}
#endif
