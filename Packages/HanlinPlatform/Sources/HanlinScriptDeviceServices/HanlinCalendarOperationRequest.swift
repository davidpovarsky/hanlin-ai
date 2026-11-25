import Foundation

/// Operation fields are patches: a supplied blank timestamp is invalid, not an
/// omitted field. Keep the legacy parser's normalization behavior unchanged.
private func calendarOperationTimestamp(_ value: String?, field: String) throws -> Date? {
    guard let value else { return nil }
    guard HanlinCalendarDateParser.nonempty(value) != nil else {
        throw HanlinCalendarRequestError.invalidDate(field)
    }
    return try HanlinCalendarDateParser.timestamp(value, field: field)
}

/// Public iOS EventKit operations. Calendar data changes are committed within one
/// invocation; no unsaved transaction is left behind for a later model turn.
public enum HanlinCalendarOperation: String, Codable, Sendable, CaseIterable {
    case authorizationStatus = "authorization_status"
    case requestAccess = "request_access"
    case listSources = "list_sources"
    case getSource = "get_source"
    case listCalendars = "list_calendars"
    case getCalendar = "get_calendar"
    case defaultCalendar = "default_calendar"
    case createCalendar = "create_calendar"
    case updateCalendar = "update_calendar"
    case deleteCalendar = "delete_calendar"
    case listEvents = "list_events"
    case getEvent = "get_event"
    case createEvent = "create_event"
    case updateEvent = "update_event"
    case deleteEvent = "delete_event"
    case listReminders = "list_reminders"
    case getReminder = "get_reminder"
    case createReminder = "create_reminder"
    case updateReminder = "update_reminder"
    case deleteReminder = "delete_reminder"
    case completeReminder = "complete_reminder"
    case reopenReminder = "reopen_reminder"
    case findByExternalIdentifier = "find_by_external_identifier"
    case refresh

    public var changesData: Bool {
        switch self {
        case .createCalendar, .updateCalendar, .deleteCalendar,
             .createEvent, .updateEvent, .deleteEvent,
             .createReminder, .updateReminder, .deleteReminder, .completeReminder, .reopenReminder:
            true
        default: false
        }
    }

    public var requiresIdentifier: Bool {
        switch self {
        case .getSource, .getCalendar, .updateCalendar, .deleteCalendar,
             .getEvent, .updateEvent, .deleteEvent,
             .getReminder, .updateReminder, .deleteReminder, .completeReminder, .reopenReminder:
            true
        default: false
        }
    }
}

public struct HanlinCalendarLocationFields: Decodable, Sendable {
    public var title: String?
    public var latitude: Double?
    public var longitude: Double?
    public var radius: Double?

    func validate() throws {
        guard (latitude == nil) == (longitude == nil),
              latitude.map({ $0.isFinite && (-90...90).contains($0) }) ?? true,
              longitude.map({ $0.isFinite && (-180...180).contains($0) }) ?? true,
              radius.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw HanlinCalendarRequestError.invalidField("structured_location")
        }
    }
}

public struct HanlinCalendarAlarmFields: Decodable, Sendable {
    public var relativeOffset: Double?
    public var absoluteDate: String?
    public var structuredLocation: HanlinCalendarLocationFields?
    public var proximity: String?

    func validate() throws {
        guard relativeOffset == nil || absoluteDate == nil,
              relativeOffset.map({ $0.isFinite && HanlinCalendarDateParser.isSupported(Date(timeIntervalSinceReferenceDate: $0)) }) ?? true,
              proximity.map({ ["none", "enter", "leave"].contains($0) }) ?? true else {
            throw HanlinCalendarRequestError.invalidField("alarms")
        }
        _ = try calendarOperationTimestamp(absoluteDate, field: "alarm.absolute_date")
        try structuredLocation?.validate()
        guard relativeOffset != nil || absoluteDate != nil || structuredLocation != nil else {
            throw HanlinCalendarRequestError.invalidField("alarm requires a time or structured_location")
        }
    }
}

public struct HanlinCalendarRecurrenceDay: Decodable, Sendable {
    public var day: Int
    public var week: Int?
}

public struct HanlinCalendarRecurrenceFields: Decodable, Sendable {
    public var frequency: String
    public var interval: Int?
    public var daysOfWeek: [HanlinCalendarRecurrenceDay]?
    public var daysOfMonth: [Int]?
    public var monthsOfYear: [Int]?
    public var weeksOfYear: [Int]?
    public var daysOfYear: [Int]?
    public var setPositions: [Int]?
    public var endDate: String?
    public var occurrenceCount: Int?

    func validate() throws {
        guard ["daily", "weekly", "monthly", "yearly"].contains(frequency),
              (interval ?? 1) > 0,
              endDate == nil || occurrenceCount == nil,
              occurrenceCount.map({ $0 > 0 }) ?? true else {
            throw HanlinCalendarRequestError.invalidField("recurrence_rules")
        }
        _ = try calendarOperationTimestamp(endDate, field: "recurrence.end_date")
        for day in daysOfWeek ?? [] {
            guard (1...7).contains(day.day), (-53...53).contains(day.week ?? 0) else {
                throw HanlinCalendarRequestError.invalidField("recurrence.days_of_week")
            }
        }
        for (name, values, bound, allowsNegative) in [
            ("days_of_month", daysOfMonth, 31, true),
            ("months_of_year", monthsOfYear, 12, false),
            ("weeks_of_year", weeksOfYear, 53, true),
            ("days_of_year", daysOfYear, 366, true),
            ("set_positions", setPositions, 366, true)
        ] {
            guard values?.allSatisfy({ $0 != 0 && $0 <= bound && $0 >= (allowsNegative ? -bound : 1) }) ?? true else {
                throw HanlinCalendarRequestError.invalidField("recurrence.\(name)")
            }
        }
    }
}

/// Only supplied fields are changed. clear_fields explicitly clears optional
/// properties; omission never erases an existing note, alarm, or recurrence.
public struct HanlinCalendarItemFields: Decodable, Sendable {
    public var title: String?
    public var calendarIdentifier: String?
    public var notes: String?
    public var location: String?
    public var url: String?
    public var timeZone: String?
    public var startDate: String?
    public var endDate: String?
    public var dueDate: String?
    public var startComponents: [String: Int]?
    public var dueComponents: [String: Int]?
    public var isAllDay: Bool?
    public var priority: Int?
    public var isCompleted: Bool?
    public var completionDate: String?
    public var availability: String?
    public var structuredLocation: HanlinCalendarLocationFields?
    public var alarms: [HanlinCalendarAlarmFields]?
    public var recurrenceRules: [HanlinCalendarRecurrenceFields]?
    public var clearFields: [String]?

    static let clearable: Set<String> = [
        "notes", "location", "url", "time_zone", "start_components",
        "due_components", "due_date", "completion_date", "alarms",
        "recurrence_rules", "structured_location"
    ]

    func validate(for operation: HanlinCalendarOperation) throws {
        if let title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.utf8.count > 4_096 {
            throw HanlinCalendarRequestError.invalidTitle
        }
        guard (notes?.utf8.count ?? 0) <= 65_536,
              priority.map({ (0...9).contains($0) }) ?? true,
              timeZone.map({ TimeZone(identifier: $0) != nil }) ?? true,
              url.map({ URL(string: $0)?.scheme != nil }) ?? true,
              availability.map({ ["not_supported", "busy", "free", "tentative", "unavailable"].contains($0) }) ?? true,
              Set(clearFields ?? []).isSubset(of: Self.clearable) else {
            throw HanlinCalendarRequestError.invalidField("item")
        }
        let start = try calendarOperationTimestamp(startDate, field: "start_date")
        let end = try calendarOperationTimestamp(endDate, field: "end_date")
        try HanlinCalendarDateParser.validateRange(start: start, end: end)
        _ = try calendarOperationTimestamp(dueDate, field: "due_date")
        _ = try calendarOperationTimestamp(completionDate, field: "completion_date")
        if operation == .createEvent, start == nil || end == nil {
            throw HanlinCalendarRequestError.missingCalendarDates
        }
        if operation == .createEvent || operation == .createReminder, title == nil {
            throw HanlinCalendarRequestError.invalidTitle
        }
        let isEvent = [.createEvent, .updateEvent].contains(operation)
        if isEvent && (dueDate != nil || dueComponents != nil || startComponents != nil ||
                       priority != nil || isCompleted != nil || completionDate != nil) {
            throw HanlinCalendarRequestError.invalidField("reminder fields cannot be used on an event")
        }
        if !isEvent && (isAllDay != nil || availability != nil || structuredLocation != nil ||
                       startDate != nil || endDate != nil) {
            throw HanlinCalendarRequestError.invalidField("event fields cannot be used on a reminder; use date components and location alarms")
        }
        let eventOnlyClear: Set<String> = ["structured_location"]
        let reminderOnlyClear: Set<String> = ["start_components", "due_components", "due_date", "completion_date"]
        if !(Set(clearFields ?? []).intersection(isEvent ? reminderOnlyClear : eventOnlyClear)).isEmpty {
            throw HanlinCalendarRequestError.invalidField("clear_fields contains a field for the wrong item type")
        }
        if isCompleted == false && completionDate != nil {
            throw HanlinCalendarRequestError.invalidField("an incomplete reminder cannot have a completion_date")
        }
        if operation == .completeReminder && isCompleted == false ||
           operation == .reopenReminder && (isCompleted == true || completionDate != nil) {
            throw HanlinCalendarRequestError.invalidField("completion fields conflict with operation")
        }
        guard dueDate == nil || dueComponents == nil else {
            throw HanlinCalendarRequestError.invalidField("supply due_date or due_components, not both")
        }
        if dueDate != nil || dueComponents != nil,
           (clearFields ?? []).contains(where: { $0 == "due_date" || $0 == "due_components" }) {
            throw HanlinCalendarRequestError.invalidField("cannot set and clear due_date/due_components")
        }
        for (name, values) in [("start_components", startComponents), ("due_components", dueComponents)] {
            if let values {
                _ = try Self.dateComponents(values, timeZone: timeZone)
                if (clearFields ?? []).contains(name) {
                    throw HanlinCalendarRequestError.invalidField("cannot set and clear \(name)")
                }
            }
        }
        let provided: [String: Bool] = [
            "notes": notes != nil, "location": location != nil, "url": url != nil,
            "time_zone": timeZone != nil, "due_date": dueDate != nil,
            "completion_date": completionDate != nil, "alarms": alarms != nil,
            "recurrence_rules": recurrenceRules != nil, "structured_location": structuredLocation != nil
        ]
        guard !(clearFields ?? []).contains(where: { provided[$0] == true }) else {
            throw HanlinCalendarRequestError.invalidField("a field cannot be set and cleared together")
        }
        try structuredLocation?.validate()
        for alarm in alarms ?? [] { try alarm.validate() }
        for rule in recurrenceRules ?? [] { try rule.validate() }
        if operation == .updateEvent || operation == .updateReminder {
            let hasMutation = [title != nil, calendarIdentifier != nil, notes != nil,
                location != nil, url != nil, timeZone != nil, startDate != nil, endDate != nil,
                dueDate != nil, startComponents != nil, dueComponents != nil, isAllDay != nil,
                priority != nil, isCompleted != nil, completionDate != nil, availability != nil,
                structuredLocation != nil, alarms != nil, recurrenceRules != nil,
                !(clearFields ?? []).isEmpty].contains(true)
            guard hasMutation else {
                throw HanlinCalendarRequestError.invalidField("update requires at least one item field or clear_fields entry")
            }
        }
    }

    static func dateComponents(_ values: [String: Int], timeZone: String?) throws -> DateComponents {
        let allowed: Set<String> = ["era", "year", "year_for_week_of_year", "quarter", "month",
            "week_of_month", "week_of_year", "weekday", "weekday_ordinal", "day",
            "hour", "minute", "second", "nanosecond"]
        guard !values.isEmpty, Set(values.keys).isSubset(of: allowed) else {
            throw HanlinCalendarRequestError.invalidField("date_components")
        }
        var result = DateComponents()
        result.calendar = Calendar(identifier: .gregorian)
        result.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        result.era = values["era"]; result.year = values["year"]
        result.yearForWeekOfYear = values["year_for_week_of_year"]; result.quarter = values["quarter"]
        result.month = values["month"]; result.weekOfMonth = values["week_of_month"]
        result.weekOfYear = values["week_of_year"]; result.weekday = values["weekday"]
        result.weekdayOrdinal = values["weekday_ordinal"]; result.day = values["day"]
        result.hour = values["hour"]; result.minute = values["minute"]
        result.second = values["second"]; result.nanosecond = values["nanosecond"]
        guard result.isValidDate(in: result.calendar ?? .current) else {
            throw HanlinCalendarRequestError.invalidField("date_components")
        }
        return result
    }
}

public struct HanlinCalendarFields: Decodable, Sendable {
    public var title: String?
    public var sourceIdentifier: String?
    public var color: String?
}

public struct HanlinCalendarOperationRequest: Decodable, Sendable {
    public var operation: HanlinCalendarOperation
    public var entityType: String?
    public var identifier: String?
    public var externalIdentifier: String?
    public var occurrenceDate: String?
    public var calendarIdentifiers: [String]?
    public var sourceIdentifier: String?
    public var keyword: String?
    public var startDate: String?
    public var endDate: String?
    public var completed: Bool?
    public var limit: Int?
    public var offset: Int?
    public var access: String?
    public var span: String?
    public var item: HanlinCalendarItemFields?
    public var calendar: HanlinCalendarFields?

    public static func decode(_ json: String) throws -> Self {
        let data = Data(json.utf8)
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HanlinCalendarRequestError.invalidField("calendar operation object")
            }
            let allowed: Set<String> = ["operation", "entity_type", "identifier", "external_identifier",
                "occurrence_date", "calendar_identifiers", "source_identifier", "keyword",
                "start_date", "end_date", "completed", "limit", "offset", "access", "span", "item", "calendar"]
            guard Set(object.keys).isSubset(of: allowed) else {
                throw HanlinCalendarRequestError.invalidField("unknown calendar argument")
            }
            if let fields = object["item"] as? [String: Any] {
                let itemKeys: Set<String> = ["title", "calendar_identifier", "notes", "location",
                    "url", "time_zone", "start_date", "end_date", "due_date", "start_components",
                    "due_components", "is_all_day", "priority", "is_completed", "completion_date",
                    "availability", "structured_location", "alarms", "recurrence_rules", "clear_fields"]
                guard Set(fields.keys).isSubset(of: itemKeys),
                      !fields.values.contains(where: { $0 is NSNull }) else {
                    throw HanlinCalendarRequestError.invalidField("unknown item field; use clear_fields to clear optional values")
                }
            }
            if let fields = object["calendar"] as? [String: Any] {
                guard Set(fields.keys).isSubset(of: ["title", "source_identifier", "color"]),
                      !fields.values.contains(where: { $0 is NSNull }) else {
                    throw HanlinCalendarRequestError.invalidField("unknown or null calendar field")
                }
            }
            func check(_ value: Any?, keys: Set<String>, name: String) throws {
                guard let value else { return }
                guard let fields = value as? [String: Any], Set(fields.keys).isSubset(of: keys),
                      !fields.values.contains(where: { $0 is NSNull }) else {
                    throw HanlinCalendarRequestError.invalidField("unsupported or null \(name) field")
                }
            }
            let locationKeys: Set<String> = ["title", "latitude", "longitude", "radius"]
            if let fields = object["item"] as? [String: Any] {
                try check(fields["structured_location"], keys: locationKeys, name: "structured_location")
                for alarm in fields["alarms"] as? [[String: Any]] ?? [] {
                    try check(alarm, keys: ["relative_offset", "absolute_date", "structured_location", "proximity"], name: "alarm")
                    try check(alarm["structured_location"], keys: locationKeys, name: "alarm.structured_location")
                }
                for rule in fields["recurrence_rules"] as? [[String: Any]] ?? [] {
                    try check(rule, keys: ["frequency", "interval", "days_of_week", "days_of_month",
                        "months_of_year", "weeks_of_year", "days_of_year", "set_positions", "end_date", "occurrence_count"], name: "recurrence")
                    for day in rule["days_of_week"] as? [[String: Any]] ?? [] {
                        try check(day, keys: ["day", "week"], name: "recurrence day")
                    }
                }
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let request = try decoder.decode(Self.self, from: data)
            try request.validate()
            return request
        } catch let error as HanlinCalendarRequestError { throw error }
        catch { throw HanlinCalendarRequestError.invalidField("calendar argument types or operation") }
    }

    public func validate() throws {
        if operation.requiresIdentifier, HanlinCalendarDateParser.nonempty(identifier) == nil {
            throw HanlinCalendarRequestError.invalidField("identifier is required for \(operation.rawValue)")
        }
        if operation == .findByExternalIdentifier,
           HanlinCalendarDateParser.nonempty(externalIdentifier) == nil {
            throw HanlinCalendarRequestError.invalidField("external_identifier")
        }
        guard entityType.map({ ["event", "reminder", "both"].contains($0) }) ?? true,
              access.map({ ["full", "write_only"].contains($0) }) ?? true,
              span.map({ ["this_event", "future_events"].contains($0) }) ?? true,
              limit.map({ (1...2_000).contains($0) }) ?? true,
              offset.map({ $0 >= 0 }) ?? true else {
            throw HanlinCalendarRequestError.invalidField("entity_type, access, span, or limit")
        }
        if access == "write_only", entityType != "event" || operation != .requestAccess {
            throw HanlinCalendarRequestError.invalidField("write_only access applies only to request_access for events")
        }
        if [.createCalendar, .updateCalendar, .deleteCalendar, .getCalendar, .defaultCalendar].contains(operation),
           !["event", "reminder"].contains(entityType ?? "") {
            throw HanlinCalendarRequestError.invalidField("entity_type must identify events or reminders")
        }
        let eventOperations: Set<HanlinCalendarOperation> = [.listEvents, .getEvent, .createEvent, .updateEvent, .deleteEvent]
        let reminderOperations: Set<HanlinCalendarOperation> = [.listReminders, .getReminder, .createReminder,
            .updateReminder, .deleteReminder, .completeReminder, .reopenReminder]
        if let entityType,
           (eventOperations.contains(operation) && entityType != "event") ||
           (reminderOperations.contains(operation) && entityType != "reminder") {
            throw HanlinCalendarRequestError.invalidField("entity_type conflicts with operation")
        }
        let itemOperations: Set<HanlinCalendarOperation> = [.createEvent, .updateEvent, .createReminder,
            .updateReminder, .completeReminder, .reopenReminder]
        if item != nil && !itemOperations.contains(operation) {
            throw HanlinCalendarRequestError.invalidField("item fields require an item mutation operation")
        }
        if calendar != nil && ![HanlinCalendarOperation.createCalendar, .updateCalendar].contains(operation) {
            throw HanlinCalendarRequestError.invalidField("calendar fields require create_calendar or update_calendar")
        }
        if let item, operation == .completeReminder || operation == .reopenReminder {
            try item.validate(for: operation)
        }
        _ = try calendarOperationTimestamp(occurrenceDate, field: "occurrence_date")
        let bounds = try queryBounds()
        try HanlinCalendarDateParser.validateRange(start: bounds.start, end: bounds.end)
        if let start = bounds.start, let end = bounds.end, start >= end {
            throw HanlinCalendarRequestError.invalidDateRange
        }
        if operation == .listEvents, bounds.start == nil || bounds.end == nil {
            throw HanlinCalendarRequestError.invalidField("list_events requires start_date and end_date")
        }
        if [.createEvent, .updateEvent, .createReminder, .updateReminder].contains(operation) {
            guard let item else { throw HanlinCalendarRequestError.invalidField("item") }
            try item.validate(for: operation)
        }
        if [.createCalendar, .updateCalendar].contains(operation) {
            guard let calendar else { throw HanlinCalendarRequestError.invalidField("calendar") }
            if operation == .createCalendar,
               HanlinCalendarDateParser.nonempty(calendar.title) == nil ||
               HanlinCalendarDateParser.nonempty(calendar.sourceIdentifier) == nil {
                throw HanlinCalendarRequestError.invalidField("create_calendar requires title and source_identifier")
            }
            if let title = calendar.title, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw HanlinCalendarRequestError.invalidTitle
            }
            if let color = calendar.color,
               color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil {
                throw HanlinCalendarRequestError.invalidField("calendar.color must be #RRGGBB")
            }
            if operation == .updateCalendar, calendar.sourceIdentifier != nil {
                throw HanlinCalendarRequestError.invalidField("a calendar source is chosen on creation and cannot be changed")
            }
            if operation == .updateCalendar, calendar.title == nil && calendar.color == nil {
                throw HanlinCalendarRequestError.invalidField("update requires at least one calendar field")
            }
        }
    }

    /// Date-only bounds include the whole named end day. Timestamp bounds are
    /// exact and half-open. Calendar arithmetic preserves 23/25-hour DST days.
    public func queryBounds(timeZone: TimeZone = .current) throws -> (start: Date?, end: Date?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func value(_ text: String?, end: Bool) throws -> Date? {
            guard let text else { return nil }
            guard HanlinCalendarDateParser.nonempty(text) != nil else {
                throw HanlinCalendarRequestError.invalidDate(end ? "end_date" : "start_date")
            }
            if text.count == 10 {
                guard let date = try HanlinCalendarDateParser.day(text, field: end ? "end_date" : "start_date", timeZone: timeZone) else { return nil }
                return end ? calendar.date(byAdding: .day, value: 1, to: date) : date
            }
            return try calendarOperationTimestamp(text, field: end ? "end_date" : "start_date")
        }
        return try (value(startDate, end: false), value(endDate, end: true))
    }
}

public struct HanlinCalendarOperationResult: Sendable {
    public let operation: HanlinCalendarOperation
    public let committed: Bool
    public let modelText: String
    public let items: [HanlinSystemEvent]

    public init(operation: HanlinCalendarOperation, committed: Bool,
                modelText: String, items: [HanlinSystemEvent] = []) {
        self.operation = operation; self.committed = committed
        self.modelText = modelText; self.items = items
    }
}
