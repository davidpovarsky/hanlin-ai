import Foundation

public enum HanlinCalendarRequestError: Error, Equatable, Sendable, LocalizedError {
    case invalidDate(String)
    case invalidField(String)
    case invalidInteger(String)
    case invalidDateRange
    case invalidEventType
    case invalidTitle
    case missingCalendarDates
    case invalidPriority
    case invalidReminderOffset
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidField(let field): "Invalid calendar argument: \(field)."
        case .invalidDate(let field): "The \(field) date is invalid."
        case .invalidInteger(let field): "The \(field) value must be an integer."
        case .invalidDateRange: "The calendar start date must not be after the end date."
        case .invalidEventType: "Choose calendar, reminder, or both for a search."
        case .invalidTitle: "Provide a nonempty event title."
        case .missingCalendarDates: "Calendar events require a start date and an end date."
        case .invalidPriority: "Reminder priority must be between 0 and 9."
        case .invalidReminderOffset: "The reminder time is outside the supported date range."
        case .timedOut: "The calendar service did not respond. The request has stopped."
        }
    }
}

/// Dates arrive from models as strings. Reject malformed supplied values instead of
/// silently changing a bounded query into an unbounded one.
public enum HanlinCalendarDateParser {
    public static func day(_ value: String?, field: String, timeZone: TimeZone = .current) throws -> Date? {
        guard let value = nonempty(value) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value,
              isSupported(date) else { throw HanlinCalendarRequestError.invalidDate(field) }
        return date
    }

    public static func timestamp(_ value: String?, field: String) throws -> Date? {
        guard let value = nonempty(value) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: value)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: value), isSupported(date) else {
            throw HanlinCalendarRequestError.invalidDate(field)
        }
        return date
    }

    public static func integer(_ value: String?, field: String) throws -> Int? {
        guard let value = nonempty(value) else { return nil }
        guard let integer = Int(value) else { throw HanlinCalendarRequestError.invalidInteger(field) }
        return integer
    }

    static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func isSupported(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && date >= .distantPast && date <= .distantFuture
    }

    static func validate(_ date: Date?, field: String) throws {
        if let date, !isSupported(date) { throw HanlinCalendarRequestError.invalidDate(field) }
    }

    static func eventIntervals(start: Date, end: Date) throws -> [DateInterval] {
        try validateRange(start: start, end: end)
        var intervals: [DateInterval] = []
        var cursor = start
        while cursor < end {
            // EventKit truncates predicates longer than four years.
            let next = min(cursor.addingTimeInterval(3 * 365 * 24 * 60 * 60), end)
            intervals.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return intervals
    }

    static func validateRange(start: Date?, end: Date?) throws {
        try validate(start, field: "start")
        try validate(end, field: "end")
        if let start, let end, start > end { throw HanlinCalendarRequestError.invalidDateRange }
    }
}

/// Shared request used by the original chat tool and by SDK hosts.
public struct HanlinCalendarSearchRequest: Sendable {
    public let keyword: String?
    public let startDate: Date?
    public let endDate: Date?
    public let location: String?
    public let eventType: String

    public var searchesCalendar: Bool { eventType == "calendar" || eventType == "both" }
    public var searchesReminders: Bool { eventType == "reminder" || eventType == "both" }
    public var hasCriteria: Bool { keyword != nil || location != nil || startDate != nil || endDate != nil }

    public init(keyword: String? = nil, startDate: Date? = nil, endDate: Date? = nil,
                location: String? = nil, eventType: String? = nil) throws {
        try HanlinCalendarDateParser.validateRange(start: startDate, end: endDate)
        let type = HanlinCalendarDateParser.nonempty(eventType)?.lowercased() ?? "both"
        guard ["calendar", "reminder", "both"].contains(type) else {
            throw HanlinCalendarRequestError.invalidEventType
        }
        self.keyword = HanlinCalendarDateParser.nonempty(keyword)
        self.startDate = startDate
        self.endDate = endDate
        self.location = HanlinCalendarDateParser.nonempty(location)
        self.eventType = type
    }

    /// Date-only searches use [start of first day, start of following day).
    /// Never broaden the lower bound into the previous day.
    public func calendarInterval(now: Date = .now, calendar: Calendar = .current) throws -> DateInterval {
        try HanlinCalendarDateParser.validate(now, field: "reference")
        let window: TimeInterval = 5 * 365 * 24 * 60 * 60
        let lower = startDate.map { calendar.startOfDay(for: $0) }
            ?? min(now, endDate ?? now).addingTimeInterval(-window)
        let upper = endDate.flatMap {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
        } ?? max(now, startDate ?? now).addingTimeInterval(window)
        guard lower.timeIntervalSinceReferenceDate.isFinite,
              upper.timeIntervalSinceReferenceDate.isFinite, lower < upper else {
            throw HanlinCalendarRequestError.invalidDateRange
        }
        return DateInterval(start: lower, end: upper)
    }

    public func matchesDate(_ date: Date?, calendar: Calendar = .current) -> Bool {
        guard let date else { return startDate == nil && endDate == nil }
        let lower = startDate.map { calendar.startOfDay(for: $0) }
        let upper = endDate.flatMap {
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0))
        }
        return (lower.map { date >= $0 } ?? true) && (upper.map { date < $0 } ?? true)
    }

}

public struct HanlinCalendarWriteRequest: Sendable {
    public let type: String
    public let title: String
    public let startDate: Date?
    public let endDate: Date?
    public let dueDate: Date?
    public let location: String?
    public let notes: String?
    public let priority: Int?
    public let reminderOffset: TimeInterval?
    public let reminderAbsoluteDate: Date?

    public init(type: String, title: String, startDate: Date? = nil, endDate: Date? = nil,
                dueDate: Date? = nil, location: String? = nil, notes: String? = nil,
                priority: Int? = nil, reminderMinutes: Int? = nil, now: Date = .now) throws {
        let type = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard type == "calendar" || type == "reminder" else { throw HanlinCalendarRequestError.invalidEventType }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HanlinCalendarRequestError.invalidTitle
        }
        try HanlinCalendarDateParser.validateRange(start: startDate, end: endDate)
        try HanlinCalendarDateParser.validate(dueDate, field: "due")
        if type == "calendar", startDate == nil || endDate == nil {
            throw HanlinCalendarRequestError.missingCalendarDates
        }
        if let priority, !(0...9).contains(priority) { throw HanlinCalendarRequestError.invalidPriority }
        var offset: TimeInterval?
        var absolute: Date?
        if type == "reminder", let minutes = reminderMinutes {
            guard minutes >= 0 else { throw HanlinCalendarRequestError.invalidReminderOffset }
            if minutes > 0 {
                // Convert before multiplying. Int.max * 60 trapped in the original tool.
                let seconds = TimeInterval(minutes) * 60
                let alarmDate = (dueDate ?? now).addingTimeInterval(dueDate == nil ? seconds : -seconds)
                guard seconds.isFinite, HanlinCalendarDateParser.isSupported(alarmDate) else {
                    throw HanlinCalendarRequestError.invalidReminderOffset
                }
                if dueDate != nil { offset = -seconds } else { absolute = alarmDate }
            }
        }
        self.type = type; self.title = title; self.startDate = startDate; self.endDate = endDate
        self.dueDate = dueDate; self.location = location; self.notes = notes; self.priority = priority
        self.reminderOffset = offset; self.reminderAbsoluteDate = absolute
    }
}

/// EventKit objects stay in the service. Host applications receive these values.
public struct HanlinSystemEvent: Sendable {
    public let type: String
    public let title: String
    public let startDate: Date?
    public let endDate: Date?
    public let dueDate: Date?
    public let location: String?
    public let notes: String?
    public let priority: Int?
    public let completed: Bool?
    public let identifier: String
    public let calendarID: String?
    public let occurrenceDate: Date?

    public init(type: String, title: String, startDate: Date? = nil, endDate: Date? = nil,
                dueDate: Date? = nil, location: String? = nil, notes: String? = nil,
                priority: Int? = nil, completed: Bool? = nil, identifier: String,
                calendarID: String? = nil, occurrenceDate: Date? = nil) {
        self.type = type; self.title = title; self.startDate = startDate; self.endDate = endDate
        self.dueDate = dueDate; self.location = location; self.notes = notes
        self.priority = priority; self.completed = completed; self.identifier = identifier
        self.calendarID = calendarID; self.occurrenceDate = occurrenceDate
    }
}
