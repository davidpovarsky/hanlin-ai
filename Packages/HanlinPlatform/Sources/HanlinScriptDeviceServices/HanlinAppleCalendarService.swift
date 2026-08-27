#if os(iOS)
import EventKit
import Foundation

public struct HanlinScriptReminderCalendar: Sendable {
    public let identifier: String
    public let title: String
    public let type: Int
    public let allowsContentModifications: Bool
}

public struct HanlinScriptReminderItem: Sendable {
    public let identifier: String
    public let calendar: HanlinScriptReminderCalendar
    public let title: String
    public let notes: String?
    public let priority: Int
    public let isCompleted: Bool
    public let completionDate: Date?
    public let dueDateComponentValues: [String: Int]?
    public let timeZoneIdentifier: String?
}

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
        identifier: String?,
        calendarIdentifier: String?,
        title: String,
        notes: String?,
        priority: Int,
        isCompleted: Bool,
        completionDate: Date?,
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
        let existing = identifier.flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
        if identifier != nil, existing == nil {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_identifier")
        }
        guard let calendar = calendarIdentifier.flatMap({ store.calendar(withIdentifier: $0) })
                ?? existing?.calendar ?? store.defaultCalendarForNewReminders() else {
            throw HanlinAppleDeviceServiceError.unavailable(.reminders)
        }
        guard calendar.allowedEntityTypes.contains(.reminder), calendar.allowsContentModifications else {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_calendar")
        }

        let reminder = existing ?? EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        reminder.priority = priority
        reminder.completionDate = completionDate
        reminder.isCompleted = isCompleted || completionDate != nil
        if let values = dueDateComponentValues {
            reminder.dueDateComponents = try Self.dateComponents(
                values,
                timeZoneIdentifier: timeZoneIdentifier
            )
        } else { reminder.dueDateComponents = nil }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    public func removeReminder(identifier: String) async throws {
        try await authorizeReminders()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_identifier")
        }
        try store.remove(reminder, commit: true)
    }

    public func reminder(identifier: String) async throws -> HanlinScriptReminderItem? {
        try await authorizeReminders()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return nil }
        return try Self.reminderValue(reminder)
    }

    public func reminderCalendars() async throws -> [HanlinScriptReminderCalendar] {
        try await authorizeReminders()
        return try store.calendars(for: .reminder).map(Self.calendarValue)
    }

    public func defaultReminderCalendar() async throws -> HanlinScriptReminderCalendar? {
        try await authorizeReminders()
        guard let calendar = store.defaultCalendarForNewReminders() else { return nil }
        return try Self.calendarValue(calendar)
    }

    public func reminders(
        completed: Bool?,
        startDate: Date?,
        endDate: Date?,
        calendarIdentifiers: [String]
    ) async throws -> [HanlinScriptReminderItem] {
        try await authorizeReminders()
        let calendars = try calendarIdentifiers.map { identifier in
            guard let calendar = store.calendar(withIdentifier: identifier),
                  calendar.allowedEntityTypes.contains(.reminder) else {
                throw HanlinAppleDeviceServiceError.invalidRequest("reminder_calendar")
            }
            return calendar
        }
        let selectedCalendars = calendars.isEmpty ? nil : calendars
        let predicate: NSPredicate = switch completed {
        case .some(true):
            store.predicateForCompletedReminders(
                withCompletionDateStarting: startDate, ending: endDate, calendars: selectedCalendars
            )
        case .some(false):
            store.predicateForIncompleteReminders(
                withDueDateStarting: startDate, ending: endDate, calendars: selectedCalendars
            )
        case .none:
            store.predicateForReminders(in: selectedCalendars)
        }
        let result: Result<[HanlinScriptReminderItem], HanlinAppleDeviceServiceError> = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders, reminders.count <= 2_000 else {
                    continuation.resume(returning: .failure(.unavailable(.reminders)))
                    return
                }
                do {
                    continuation.resume(returning: .success(try reminders.map(Self.reminderValue)))
                } catch let error as HanlinAppleDeviceServiceError {
                    continuation.resume(returning: .failure(error))
                } catch {
                    continuation.resume(returning: .failure(.invalidRequest("reminder_result")))
                }
            }
        }
        return try result.get()
    }

    private func authorizeReminders() async throws {
        guard try await requestReminderAuthorization() else {
            throw HanlinAppleDeviceServiceError.denied(.reminders)
        }
    }

    nonisolated private static func calendarValue(_ calendar: EKCalendar) throws -> HanlinScriptReminderCalendar {
        guard !calendar.calendarIdentifier.isEmpty, calendar.calendarIdentifier.utf8.count <= 512,
              calendar.title.utf8.count <= 4_096 else {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_calendar_result")
        }
        return .init(identifier: calendar.calendarIdentifier, title: calendar.title,
                     type: calendar.type.rawValue,
                     allowsContentModifications: calendar.allowsContentModifications)
    }

    nonisolated private static func reminderValue(_ reminder: EKReminder) throws -> HanlinScriptReminderItem {
        guard !reminder.calendarItemIdentifier.isEmpty,
              reminder.calendarItemIdentifier.utf8.count <= 512,
              reminder.title?.utf8.count ?? 0 <= 4_096,
              reminder.notes?.utf8.count ?? 0 <= 65_536 else {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_result")
        }
        let due = reminder.dueDateComponents
        let values = due.map { components in
            [
                "era": components.era, "year": components.year,
                "yearForWeekOfYear": components.yearForWeekOfYear, "quarter": components.quarter,
                "month": components.month, "weekOfMonth": components.weekOfMonth,
                "weekOfYear": components.weekOfYear, "weekday": components.weekday,
                "weekdayOrdinal": components.weekdayOrdinal, "day": components.day,
                "hour": components.hour, "minute": components.minute,
                "second": components.second, "nanosecond": components.nanosecond,
            ].compactMapValues { $0 }
        }
        return try .init(
            identifier: reminder.calendarItemIdentifier,
            calendar: calendarValue(reminder.calendar),
            title: reminder.title ?? "", notes: reminder.notes, priority: reminder.priority,
            isCompleted: reminder.isCompleted, completionDate: reminder.completionDate,
            dueDateComponentValues: values, timeZoneIdentifier: due?.timeZone?.identifier
        )
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
