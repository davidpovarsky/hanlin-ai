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
    let store: EKEventStore

    public init(store: EKEventStore = .init()) { self.store = store }

    public func requestCalendarAuthorization() async throws -> Bool {
        try await HanlinCalendarCallbackOperation<Bool>().value { completion in
            store.requestFullAccessToEvents { @Sendable granted, error in
                completion(error.map { .failure($0) } ?? .success(granted))
            }
            return nil
        }
    }

    public func requestReminderAuthorization() async throws -> Bool {
        try await HanlinCalendarCallbackOperation<Bool>().value { completion in
            store.requestFullAccessToReminders { @Sendable granted, error in
                completion(error.map { .failure($0) } ?? .success(granted))
            }
            return nil
        }
    }

    /// The original chat calendar/reminder implementation, now shared by SDK hosts.
    public func search(_ request: HanlinCalendarSearchRequest) async throws -> [HanlinSystemEvent] {
        try Task.checkCancellation()
        guard request.hasCriteria else { return [] }
        let calendarGranted = request.searchesCalendar ? try await requestCalendarAuthorization() : false
        let remindersGranted = request.searchesReminders ? try await requestReminderAuthorization() : false
        try Task.checkCancellation()
        guard calendarGranted || remindersGranted else {
            throw HanlinAppleDeviceServiceError.denied(request.searchesCalendar ? .calendar : .reminders)
        }
        var result: [HanlinSystemEvent] = []
        if calendarGranted {
            let interval = try request.calendarInterval()
            for event in try calendarEvents(from: interval.start, to: interval.end) {
                let title = event.title ?? ""
                let notes = event.notes ?? ""
                let keywordMatches = request.keyword.map {
                    title.localizedCaseInsensitiveContains($0) || notes.localizedCaseInsensitiveContains($0)
                } ?? true
                let locationMatches = request.location.map {
                    (event.location ?? "").localizedCaseInsensitiveContains($0)
                } ?? true
                let dateMatches = request.matchesDate(event.startDate)
                if keywordMatches && locationMatches && dateMatches {
                    result.append(.init(type: "calendar", title: title, startDate: event.startDate,
                        endDate: event.endDate, location: event.location, notes: event.notes,
                        identifier: event.calendarItemIdentifier, calendarID: event.calendar.calendarIdentifier,
                        occurrenceDate: event.occurrenceDate))
                }
            }
        }
        if remindersGranted {
            let reminders: [HanlinSystemEvent] = try await fetchReminders(
                matching: store.predicateForReminders(in: nil)
            ) { reminders in
                reminders.map { reminder in
                    .init(type: "reminder", title: reminder.title ?? "",
                        dueDate: reminder.dueDateComponents?.date, notes: reminder.notes,
                        priority: reminder.priority == 0 ? nil : reminder.priority,
                        completed: reminder.isCompleted, identifier: reminder.calendarItemIdentifier,
                        calendarID: reminder.calendar.calendarIdentifier)
                }
            }
            result += reminders.filter { reminder in
                let notes = reminder.notes ?? ""
                let keywordMatches = request.keyword.map {
                    reminder.title.localizedCaseInsensitiveContains($0) || notes.localizedCaseInsensitiveContains($0)
                } ?? true
                let locationMatches = request.location.map {
                    reminder.title.localizedCaseInsensitiveContains($0) || notes.localizedCaseInsensitiveContains($0)
                } ?? true
                let dateMatches = request.matchesDate(reminder.dueDate)
                return keywordMatches && locationMatches && dateMatches
            }
        }
        try Task.checkCancellation()
        return result
    }

    public func write(_ request: HanlinCalendarWriteRequest) async throws -> HanlinSystemEvent {
        try Task.checkCancellation()
        if request.type == "calendar" {
            guard try await requestCalendarAuthorization() else {
                throw HanlinAppleDeviceServiceError.denied(.calendar)
            }
            try Task.checkCancellation()
            guard let calendar = store.defaultCalendarForNewEvents,
                  calendar.allowedEntityTypes.contains(.event), calendar.allowsContentModifications else {
                throw HanlinAppleDeviceServiceError.unavailable(.calendar)
            }
            let event = EKEvent(eventStore: store)
            event.title = request.title; event.startDate = request.startDate; event.endDate = request.endDate
            event.location = request.location; event.notes = request.notes; event.calendar = calendar
            try store.save(event, span: .thisEvent)
            return .init(type: request.type, title: request.title, startDate: request.startDate,
                endDate: request.endDate, location: request.location, notes: request.notes,
                identifier: event.calendarItemIdentifier, calendarID: event.calendar.calendarIdentifier,
                occurrenceDate: event.occurrenceDate)
        }
        let due = request.dueDate.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second, .timeZone], from: $0)
        }
        let values = due.map { components in
            ["year": components.year, "month": components.month, "day": components.day,
             "hour": components.hour, "minute": components.minute, "second": components.second].compactMapValues { $0 }
        }
        let identifier = try await saveReminder(identifier: nil, calendarIdentifier: nil, title: request.title,
            notes: request.notes, priority: request.priority ?? 0, isCompleted: false, completionDate: nil,
            dueDateComponentValues: values, timeZoneIdentifier: due?.timeZone?.identifier,
            alarmRelativeOffset: request.reminderOffset, alarmAbsoluteDate: request.reminderAbsoluteDate)
        return .init(type: request.type, title: request.title, dueDate: request.dueDate, notes: request.notes,
            priority: request.priority, completed: false, identifier: identifier)
    }

    /// EventKit shortens a single predicate to four years. Partition the original
    /// five-years-each-way search so current and future events are not silently lost.
    func calendarEvents(from startDate: Date, to endDate: Date, calendars: [EKCalendar]? = nil) throws -> [EKEvent] {
        let intervals = try HanlinCalendarDateParser.eventIntervals(start: startDate, end: endDate)
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var result: [EKEvent] = []
        var seen: Set<String> = []
        for interval in intervals {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw HanlinCalendarRequestError.timedOut }
            let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
            for event in store.events(matching: predicate) {
                // Recurring occurrences share an identifier but have different dates.
                let key = event.calendarItemIdentifier + "/" + String(event.startDate?.timeIntervalSinceReferenceDate ?? 0)
                if seen.insert(key).inserted { result.append(event) }
            }
        }
        return result
    }

    func fetchReminders<Value: Sendable>(
        matching predicate: NSPredicate,
        transform: @escaping @Sendable ([EKReminder]) throws -> Value
    ) async throws -> Value {
        try await HanlinCalendarCallbackOperation<Value>().value { completion in
            let token = store.fetchReminders(matching: predicate) { @Sendable reminders in
                guard let reminders else {
                    completion(.failure(HanlinAppleDeviceServiceError.unavailable(.reminders)))
                    return
                }
                completion(Result { try transform(reminders) })
            }
            return { self.store.cancelFetchRequest(token) }
        }
    }

    public func events(from startDate: Date, to endDate: Date) throws -> [HanlinScriptCalendarItem] {
        try calendarEvents(from: startDate, to: endDate).compactMap { event in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            return .init(id: event.eventIdentifier ?? "", title: event.title ?? "",
                         startDate: start, endDate: end, isAllDay: event.isAllDay)
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
        timeZoneIdentifier: String?,
        alarmRelativeOffset: TimeInterval? = nil,
        alarmAbsoluteDate: Date? = nil
    ) async throws -> String {
        guard !title.isEmpty, title.utf8.count <= 4_096,
              notes?.utf8.count ?? 0 <= 65_536,
              (0 ... 9).contains(priority) else {
            throw HanlinAppleDeviceServiceError.invalidRequest("reminder_payload")
        }
        guard alarmRelativeOffset?.isFinite ?? true,
              alarmAbsoluteDate.map(HanlinCalendarDateParser.isSupported) ?? true,
              alarmRelativeOffset == nil || alarmAbsoluteDate == nil else {
            throw HanlinCalendarRequestError.invalidReminderOffset
        }
        guard try await requestReminderAuthorization() else {
            throw HanlinAppleDeviceServiceError.denied(.reminders)
        }
        try Task.checkCancellation()
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
        if let offset = alarmRelativeOffset { reminder.addAlarm(EKAlarm(relativeOffset: offset)) }
        if let date = alarmAbsoluteDate { reminder.addAlarm(EKAlarm(absoluteDate: date)) }
        try Task.checkCancellation()
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
        try HanlinCalendarDateParser.validateRange(start: startDate, end: endDate)
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
        return try await fetchReminders(matching: predicate) { reminders in
            guard reminders.count <= 2_000 else {
                throw HanlinAppleDeviceServiceError.unavailable(.reminders)
            }
            return try reminders.map(Self.reminderValue)
        }
    }

    private func authorizeReminders() async throws {
        guard try await requestReminderAuthorization() else {
            throw HanlinAppleDeviceServiceError.denied(.reminders)
        }
        try Task.checkCancellation()
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
        guard let calendar = reminder.calendar,
              !reminder.calendarItemIdentifier.isEmpty,
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
            calendar: calendarValue(calendar),
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
