#if os(iOS)
import EventKit
import Foundation

@MainActor
public final class HanlinAppleCalendarService {
    private let store: EKEventStore

    public init(store: EKEventStore = .init()) { self.store = store }

    public func requestCalendarAuthorization() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func requestReminderAuthorization() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public func events(from startDate: Date, to endDate: Date) throws -> [HanlinScriptCalendarItem] {
        guard startDate <= endDate else { throw HanlinAppleDeviceServiceError.invalidRequest("calendar_date_range") }
        return store.events(matching: store.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )).map {
            .init(
                id: $0.eventIdentifier ?? "",
                title: $0.title ?? "",
                startDate: $0.startDate,
                endDate: $0.endDate,
                isAllDay: $0.isAllDay
            )
        }
    }

    public func saveReminder(
        title: String,
        notes: String?,
        priority: Int,
        dueDateComponentValues: [String: Int]?,
        timeZoneIdentifier: String?
    ) async throws -> String {
        guard !title.isEmpty, title.utf8.count <= 4_096,
              notes?.utf8.count ?? 0 <= 65_536,
              (0 ... 9).contains(priority) else {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_payload")
        }
        guard try await requestReminderAuthorization() else {
            throw HanlinAppleDeviceServiceError.denied(.reminders)
        }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw HanlinAppleDeviceServiceError.unavailable(.reminders)
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority
        if let values = dueDateComponentValues {
            reminder.dueDateComponents = try Self.dateComponents(
                values,
                timeZoneIdentifier: timeZoneIdentifier
            )
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    private static func dateComponents(
        _ values: [String: Int],
        timeZoneIdentifier: String?
    ) throws -> DateComponents {
        guard !values.isEmpty else {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_due_date")
        }
        var components = DateComponents()
        components.calendar = .current
        if let timeZoneIdentifier {
            guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
                throw HanlinAppleDeviceServiceError.invalidRequest("reminder_time_zone")
            }
            components.timeZone = timeZone
        } else {
            components.timeZone = .current
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
        guard components.isValidDate(in: components.calendar ?? .current) else {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_due_date")
        }
        return components
    }
}
#endif
