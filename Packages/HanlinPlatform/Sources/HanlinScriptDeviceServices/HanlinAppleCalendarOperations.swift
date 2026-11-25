#if os(iOS)
import CoreLocation
import EventKit
import Foundation
import UIKit

/// The chat and SDK share this EventKit store, permissions, identifiers, and errors.
extension HanlinAppleCalendarService {
    public func execute(_ request: HanlinCalendarOperationRequest) async throws -> HanlinCalendarOperationResult {
        try request.validate()
        try Task.checkCancellation()
        if request.operation == .authorizationStatus {
            return operationResult(request, data: authorizationValues())
        }
        if request.operation == .requestAccess {
            if request.access == "write_only" {
                let granted = try await store.requestWriteOnlyAccessToEvents()
                return operationResult(request, data: ["granted": granted, "authorization": authorizationValues()])
            }
            try await authorizeOperation(request)
            return operationResult(request, data: ["granted": true, "authorization": authorizationValues()])
        }
        try await authorizeOperation(request)
        try Task.checkCancellation()
        switch request.operation {
        case .authorizationStatus, .requestAccess:
            return operationResult(request, data: authorizationValues())
        case .refresh:
            store.refreshSourcesIfNecessary()
            return operationResult(request, data: ["refresh_requested": true])
        case .listSources:
            var seen = Set<String>()
            let sources = (store.sources + store.delegateSources).filter { seen.insert($0.sourceIdentifier).inserted }
            return operationResult(request, data: sources.map(Self.sourceJSON))
        case .getSource:
            guard let source = store.source(withIdentifier: request.identifier ?? "") else {
                throw HanlinCalendarRequestError.invalidField("source identifier was not found")
            }
            return operationResult(request, data: Self.sourceJSON(source))
        case .listCalendars:
            let types: [EKEntityType] = request.entityType == "event" ? [.event] :
                request.entityType == "reminder" ? [.reminder] : [.event, .reminder]
            var seen = Set<String>()
            let calendars = types.flatMap { store.calendars(for: $0) }.filter {
                seen.insert($0.calendarIdentifier).inserted &&
                (request.sourceIdentifier == nil || $0.source?.sourceIdentifier == request.sourceIdentifier)
            }
            return operationResult(request, data: calendars.map(Self.calendarJSON))
        case .getCalendar:
            return operationResult(request, data: Self.calendarJSON(try selectedCalendar(request.identifier, entity: request.entityType)))
        case .defaultCalendar:
            let calendar = request.entityType == "reminder" ? store.defaultCalendarForNewReminders() : store.defaultCalendarForNewEvents
            return operationResult(request, data: Self.optional(calendar.map(Self.calendarJSON)))
        case .createCalendar, .updateCalendar:
            return try saveCalendarOperation(request)
        case .deleteCalendar:
            let calendar = try selectedCalendar(request.identifier, entity: request.entityType)
            guard !calendar.isImmutable else {
                throw HanlinCalendarRequestError.invalidField("calendar is read-only")
            }
            let value = Self.calendarJSON(calendar)
            try store.removeCalendar(calendar, commit: true)
            return operationResult(request, committed: true, data: ["deleted_calendar": value])
        case .listEvents:
            let bounds = try request.queryBounds()
            guard let start = bounds.start, let end = bounds.end else {
                throw HanlinCalendarRequestError.invalidField("event date range")
            }
            let calendars = try selectedCalendars(request.calendarIdentifiers, entity: "event")
            let events = try calendarEvents(from: start, to: end, calendars: calendars)
                .filter { Self.matchesKeyword($0, request.keyword) }
                .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            let snapshots = events.dropFirst(request.offset ?? 0).prefix(request.limit ?? 200).map(Self.snapshot)
            return operationResult(request, data: [
                "items": snapshots.map { Self.parsedJSON($0.json) },
                "total_count": events.count, "truncated": events.count > (request.offset ?? 0) + snapshots.count
            ])
        case .getEvent:
            let event = try resolvedEvent(identifier: request.identifier ?? "", occurrenceDate: request.occurrenceDate)
            return operationResult(request, data: Self.parsedJSON(Self.snapshot(event).json))
        case .createEvent, .updateEvent:
            return try saveEventOperation(request)
        case .deleteEvent:
            let event = try resolvedEvent(identifier: request.identifier ?? "", occurrenceDate: request.occurrenceDate)
            try ensureWritable(event.calendar)
            let snapshot = Self.snapshot(event)
            try store.remove(event, span: request.span == "future_events" ? .futureEvents : .thisEvent, commit: true)
            return operationResult(request, committed: true, data: [
                "deleted_item": Self.parsedJSON(snapshot.json), "span": request.span ?? "this_event"
            ])
        case .listReminders:
            return try await listReminderOperation(request)
        case .getReminder:
            let reminder = try resolvedReminder(request.identifier)
            return operationResult(request, data: Self.parsedJSON(Self.snapshot(reminder).json))
        case .createReminder, .updateReminder, .completeReminder, .reopenReminder:
            return try saveReminderOperation(request)
        case .deleteReminder:
            let reminder = try resolvedReminder(request.identifier)
            try ensureWritable(reminder.calendar)
            let snapshot = Self.snapshot(reminder)
            try store.remove(reminder, commit: true)
            return operationResult(request, committed: true, data: ["deleted_item": Self.parsedJSON(snapshot.json)])
        case .findByExternalIdentifier:
            let items = store.calendarItems(withExternalIdentifier: request.externalIdentifier ?? "")
                .filter { item in
                    request.entityType == nil || request.entityType == "both" ||
                    (request.entityType == "event" && item is EKEvent) ||
                    (request.entityType == "reminder" && item is EKReminder)
                }.map(Self.snapshot)
            return operationResult(request, data: items.map { Self.parsedJSON($0.json) })
        }
    }

    /// EventKitUI needs the actual EKEvent from the same store. Never rebind a
    /// missing identifier by title, which could open or edit a different record.
    public func eventForPresentation(identifier: String, occurrenceDate: Date? = nil) async throws -> EKEvent {
        guard try await requestCalendarAuthorization() else {
            throw HanlinAppleDeviceServiceError.denied(.calendar)
        }
        try Task.checkCancellation()
        return try resolvedEvent(identifier: identifier, occurrenceDate: occurrenceDate.map(Self.iso))
    }

    private func authorizeOperation(_ request: HanlinCalendarOperationRequest) async throws {
        let eventOnly: Set<HanlinCalendarOperation> = [.listEvents, .getEvent, .createEvent, .updateEvent, .deleteEvent]
        let reminderOnly: Set<HanlinCalendarOperation> = [.listReminders, .getReminder, .createReminder,
            .updateReminder, .deleteReminder, .completeReminder, .reopenReminder]
        let entity = eventOnly.contains(request.operation) ? "event" :
            reminderOnly.contains(request.operation) ? "reminder" : request.entityType ?? "both"
        if entity != "reminder", !(try await requestCalendarAuthorization()) {
            throw HanlinAppleDeviceServiceError.denied(.calendar)
        }
        if entity != "event", !(try await requestReminderAuthorization()) {
            throw HanlinAppleDeviceServiceError.denied(.reminders)
        }
    }

    private func authorizationValues() -> [String: Any] {
        func value(_ entity: EKEntityType) -> String {
            switch EKEventStore.authorizationStatus(for: entity) {
            case .notDetermined: "not_determined"
            case .restricted: "restricted"
            case .denied: "denied"
            case .fullAccess: "full"
            case .writeOnly: "write_only"
            @unknown default: "unknown"
            }
        }
        return ["event": value(.event), "reminder": value(.reminder)]
    }

    private func selectedCalendar(_ identifier: String?, entity: String?) throws -> EKCalendar {
        guard let identifier, let calendar = store.calendar(withIdentifier: identifier),
              entity == nil || entity == "both" ||
                (entity == "event" && calendar.allowedEntityTypes.contains(.event)) ||
                (entity == "reminder" && calendar.allowedEntityTypes.contains(.reminder)) else {
            throw HanlinCalendarRequestError.invalidField("calendar identifier was not found for this entity type")
        }
        return calendar
    }

    private func selectedCalendars(_ identifiers: [String]?, entity: String) throws -> [EKCalendar]? {
        guard let identifiers, !identifiers.isEmpty else { return nil }
        return try identifiers.map { try selectedCalendar($0, entity: entity) }
    }

    private func ensureWritable(_ calendar: EKCalendar?) throws {
        guard let calendar, calendar.allowsContentModifications else {
            throw HanlinCalendarRequestError.invalidField("calendar does not allow content changes")
        }
    }

    private func resolvedReminder(_ identifier: String?) throws -> EKReminder {
        guard let identifier, let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw HanlinCalendarRequestError.invalidField("reminder identifier was not found; no replacement was created")
        }
        return reminder
    }

    private func resolvedEvent(identifier: String, occurrenceDate: String?) throws -> EKEvent {
        guard let event = store.calendarItem(withIdentifier: identifier) as? EKEvent ??
                store.event(withIdentifier: identifier) else {
            throw HanlinCalendarRequestError.invalidField("event identifier was not found; no replacement was created")
        }
        guard let occurrence = try HanlinCalendarDateParser.timestamp(occurrenceDate, field: "occurrence_date") else { return event }
        if event.occurrenceDate == occurrence || event.startDate == occurrence { return event }
        let start = Calendar.current.startOfDay(for: occurrence)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            throw HanlinCalendarRequestError.invalidDate("occurrence_date")
        }
        let candidates = try calendarEvents(from: start, to: end, calendars: [event.calendar])
        guard let matched = candidates.first(where: {
            ($0.calendarItemIdentifier == event.calendarItemIdentifier ||
             $0.eventIdentifier == event.eventIdentifier ||
             ($0.calendarItemExternalIdentifier != nil && $0.calendarItemExternalIdentifier == event.calendarItemExternalIdentifier)) &&
            ($0.occurrenceDate == occurrence || $0.startDate == occurrence)
        }) else {
            throw HanlinCalendarRequestError.invalidField("the specified recurring occurrence was not found")
        }
        return matched
    }

    private func saveCalendarOperation(_ request: HanlinCalendarOperationRequest) throws -> HanlinCalendarOperationResult {
        guard let fields = request.calendar else { throw HanlinCalendarRequestError.invalidField("calendar") }
        let calendar: EKCalendar
        if request.operation == .createCalendar {
            guard let sourceID = fields.sourceIdentifier, let source = store.source(withIdentifier: sourceID) else {
                throw HanlinCalendarRequestError.invalidField("source_identifier")
            }
            calendar = EKCalendar(for: request.entityType == "reminder" ? .reminder : .event, eventStore: store)
            calendar.source = source
        } else {
            calendar = try selectedCalendar(request.identifier, entity: request.entityType)
            guard !calendar.isImmutable else { throw HanlinCalendarRequestError.invalidField("calendar metadata is immutable") }
        }
        if let title = fields.title { calendar.title = title }
        if let hex = fields.color, let rgb = UInt32(hex.dropFirst(), radix: 16) {
            calendar.cgColor = UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1).cgColor
        }
        do { try store.saveCalendar(calendar, commit: true) }
        catch { store.reset(); throw error }
        return operationResult(request, committed: true, data: Self.calendarJSON(calendar))
    }

    private func saveEventOperation(_ request: HanlinCalendarOperationRequest) throws -> HanlinCalendarOperationResult {
        guard let fields = request.item else { throw HanlinCalendarRequestError.invalidField("item") }
        let event = request.operation == .createEvent ? EKEvent(eventStore: store) :
            try resolvedEvent(identifier: request.identifier ?? "", occurrenceDate: request.occurrenceDate)
        if request.operation == .updateEvent { try ensureWritable(event.calendar) }
        let target = try fields.calendarIdentifier.map { try selectedCalendar($0, entity: "event") }
            ?? event.calendar ?? store.defaultCalendarForNewEvents
        try ensureWritable(target)
        do {
            event.calendar = target
            try applyCommon(fields, to: event)
            if let text = fields.startDate { event.startDate = try HanlinCalendarDateParser.timestamp(text, field: "start_date") }
            if let text = fields.endDate { event.endDate = try HanlinCalendarDateParser.timestamp(text, field: "end_date") }
            guard let start = event.startDate, let end = event.endDate, start < end else {
                throw HanlinCalendarRequestError.invalidDateRange
            }
            if let allDay = fields.isAllDay { event.isAllDay = allDay }
            if let availability = fields.availability {
                switch availability {
                case "free": event.availability = .free
                case "tentative": event.availability = .tentative
                case "unavailable": event.availability = .unavailable
                case "not_supported": event.availability = .notSupported
                default: event.availability = .busy
                }
            }
            if let location = fields.structuredLocation { event.structuredLocation = Self.location(location) }
            if fields.clearFields?.contains("structured_location") == true { event.structuredLocation = nil }
            try store.save(event, span: request.span == "future_events" ? .futureEvents : .thisEvent, commit: true)
        } catch { store.reset(); throw error }
        // A commit is final. Do not check cancellation afterwards and invite a duplicate.
        let saved = Self.snapshot(event)
        return operationResult(request, committed: true, data: Self.parsedJSON(saved.json), items: [saved.item])
    }

    private func saveReminderOperation(_ request: HanlinCalendarOperationRequest) throws -> HanlinCalendarOperationResult {
        let reminder = request.operation == .createReminder ? EKReminder(eventStore: store) :
            try resolvedReminder(request.identifier)
        if request.operation != .createReminder { try ensureWritable(reminder.calendar) }
        let target = try request.item?.calendarIdentifier.map { try selectedCalendar($0, entity: "reminder") }
            ?? reminder.calendar ?? store.defaultCalendarForNewReminders()
        try ensureWritable(target)
        do {
            reminder.calendar = target
            if let fields = request.item {
                try applyCommon(fields, to: reminder)
                if let priority = fields.priority { reminder.priority = priority }
                if let components = fields.startComponents {
                    reminder.startDateComponents = try HanlinCalendarItemFields.dateComponents(components, timeZone: fields.timeZone)
                }
                if let components = fields.dueComponents {
                    reminder.dueDateComponents = try HanlinCalendarItemFields.dateComponents(components, timeZone: fields.timeZone)
                }
                if let text = fields.dueDate, let due = try HanlinCalendarDateParser.timestamp(text, field: "due_date") {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = fields.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
                    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
                    components.calendar = calendar; components.timeZone = calendar.timeZone
                    reminder.dueDateComponents = components
                }
                if let zone = fields.timeZone.flatMap(TimeZone.init(identifier:)) {
                    if var due = reminder.dueDateComponents { due.timeZone = zone; reminder.dueDateComponents = due }
                    if var start = reminder.startDateComponents { start.timeZone = zone; reminder.startDateComponents = start }
                }
                if fields.clearFields?.contains("time_zone") == true {
                    if var due = reminder.dueDateComponents { due.timeZone = nil; reminder.dueDateComponents = due }
                    if var start = reminder.startDateComponents { start.timeZone = nil; reminder.startDateComponents = start }
                }
                if let completed = fields.isCompleted { reminder.isCompleted = completed }
                if let text = fields.completionDate {
                    reminder.completionDate = try HanlinCalendarDateParser.timestamp(text, field: "completion_date")
                }
                if fields.clearFields?.contains("start_components") == true { reminder.startDateComponents = nil }
                if fields.clearFields?.contains("due_components") == true || fields.clearFields?.contains("due_date") == true {
                    reminder.dueDateComponents = nil
                }
                if fields.clearFields?.contains("completion_date") == true { reminder.completionDate = nil }
            }
            if request.operation == .completeReminder { reminder.isCompleted = true }
            if request.operation == .reopenReminder { reminder.isCompleted = false }
            try store.save(reminder, commit: true)
        } catch { store.reset(); throw error }
        let saved = Self.snapshot(reminder)
        return operationResult(request, committed: true, data: Self.parsedJSON(saved.json), items: [saved.item])
    }

    private func applyCommon(_ fields: HanlinCalendarItemFields, to item: EKCalendarItem) throws {
        if let title = fields.title { item.title = title }
        if let notes = fields.notes { item.notes = notes }
        if let location = fields.location { item.location = location }
        if let url = fields.url { item.url = URL(string: url) }
        if let zone = fields.timeZone { item.timeZone = TimeZone(identifier: zone) }
        if let alarms = fields.alarms { item.alarms = try alarms.map(Self.alarm) }
        if let rules = fields.recurrenceRules { item.recurrenceRules = try rules.map(Self.rule) }
        for field in fields.clearFields ?? [] {
            switch field {
            case "notes": item.notes = nil
            case "location": item.location = nil
            case "url": item.url = nil
            case "time_zone": item.timeZone = nil
            case "alarms": item.alarms = nil
            case "recurrence_rules": item.recurrenceRules = nil
            default: break
            }
        }
    }

    private func listReminderOperation(_ request: HanlinCalendarOperationRequest) async throws -> HanlinCalendarOperationResult {
        let calendars = try selectedCalendars(request.calendarIdentifiers, entity: "reminder")
        let bounds = try request.queryBounds()
        let predicate: NSPredicate
        switch request.completed {
        case true?: predicate = store.predicateForCompletedReminders(withCompletionDateStarting: bounds.start, ending: bounds.end, calendars: calendars)
        case false?: predicate = store.predicateForIncompleteReminders(withDueDateStarting: bounds.start, ending: bounds.end, calendars: calendars)
        case nil: predicate = store.predicateForReminders(in: calendars)
        }
        let snapshots: [CalendarSnapshot] = try await fetchReminders(matching: predicate) { reminders in
            reminders.filter { item in
                guard Self.matchesKeyword(item, request.keyword) else { return false }
                let date = request.completed == true ? item.completionDate : item.dueDateComponents?.date
                if bounds.start == nil && bounds.end == nil { return true }
                guard let date else { return false }
                return (bounds.start.map { date >= $0 } ?? true) && (bounds.end.map { date < $0 } ?? true)
            }.sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
             .map(Self.snapshot)
        }
        let limited = Array(snapshots.dropFirst(request.offset ?? 0).prefix(request.limit ?? 200))
        return operationResult(request, data: ["items": limited.map { Self.parsedJSON($0.json) },
            "total_count": snapshots.count, "truncated": snapshots.count > (request.offset ?? 0) + limited.count])
    }

    nonisolated private static func location(_ fields: HanlinCalendarLocationFields) -> EKStructuredLocation {
        let location = EKStructuredLocation(title: fields.title ?? "")
        if let latitude = fields.latitude, let longitude = fields.longitude {
            location.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
        }
        if let radius = fields.radius { location.radius = radius }
        return location
    }

    nonisolated private static func alarm(_ fields: HanlinCalendarAlarmFields) throws -> EKAlarm {
        let alarm: EKAlarm
        if let date = try HanlinCalendarDateParser.timestamp(fields.absoluteDate, field: "alarm.absolute_date") {
            alarm = EKAlarm(absoluteDate: date)
        } else { alarm = EKAlarm(relativeOffset: fields.relativeOffset ?? 0) }
        if let location = fields.structuredLocation { alarm.structuredLocation = Self.location(location) }
        switch fields.proximity {
        case "enter": alarm.proximity = .enter
        case "leave": alarm.proximity = .leave
        default: alarm.proximity = .none
        }
        return alarm
    }

    nonisolated private static func rule(_ fields: HanlinCalendarRecurrenceFields) throws -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency
        switch fields.frequency {
        case "weekly": frequency = .weekly
        case "monthly": frequency = .monthly
        case "yearly": frequency = .yearly
        default: frequency = .daily
        }
        let end: EKRecurrenceEnd?
        if let date = try HanlinCalendarDateParser.timestamp(fields.endDate, field: "recurrence.end_date") {
            end = EKRecurrenceEnd(end: date)
        } else if let count = fields.occurrenceCount { end = EKRecurrenceEnd(occurrenceCount: count) }
        else { end = nil }
        let days = try fields.daysOfWeek?.map { value -> EKRecurrenceDayOfWeek in
            guard let day = EKWeekday(rawValue: value.day) else { throw HanlinCalendarRequestError.invalidField("weekday") }
            return EKRecurrenceDayOfWeek(day, weekNumber: value.week ?? 0)
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: fields.interval ?? 1,
            daysOfTheWeek: days, daysOfTheMonth: fields.daysOfMonth?.map(NSNumber.init(value:)),
            monthsOfTheYear: fields.monthsOfYear?.map(NSNumber.init(value:)),
            weeksOfTheYear: fields.weeksOfYear?.map(NSNumber.init(value:)),
            daysOfTheYear: fields.daysOfYear?.map(NSNumber.init(value:)),
            setPositions: fields.setPositions?.map(NSNumber.init(value:)), end: end)
    }

    private struct CalendarSnapshot: Sendable {
        var json: String
        var item: HanlinSystemEvent
    }

    nonisolated private static func snapshot(_ item: EKCalendarItem) -> CalendarSnapshot {
        var value: [String: Any] = [
            "identifier": item.calendarItemIdentifier,
            "external_identifier": optional(item.calendarItemExternalIdentifier),
            "calendar_identifier": optional(item.calendar?.calendarIdentifier),
            "title": item.title ?? "", "notes": optional(item.notes), "location": optional(item.location),
            "url": optional(item.url?.absoluteString), "time_zone": optional(item.timeZone?.identifier),
            "created_at": optional(item.creationDate.map(iso)),
            "modified_at": optional(item.lastModifiedDate.map(iso)),
            "alarms": (item.alarms ?? []).map(alarmJSON),
            "recurrence_rules": (item.recurrenceRules ?? []).map(ruleJSON),
            "attendees": (item.attendees ?? []).map(participantJSON),
            "read_only_fields": ["identifier", "external_identifier", "created_at", "modified_at",
                "attendees", "organizer", "status", "is_detached", "occurrence_date", "birthday_contact_identifier"]
        ]
        let summary: HanlinSystemEvent
        if let event = item as? EKEvent {
            value["type"] = "calendar"; value["event_identifier"] = optional(event.eventIdentifier)
            value["start_date"] = optional(event.startDate.map(iso))
            value["end_date"] = optional(event.endDate.map(iso))
            value["is_all_day"] = event.isAllDay; value["availability"] = event.availability.rawValue
            value["status"] = event.status.rawValue; value["is_detached"] = event.isDetached
            value["occurrence_date"] = optional(event.occurrenceDate.map(iso))
            value["structured_location"] = optional(event.structuredLocation.map(locationJSON))
            value["organizer"] = optional(event.organizer.map(participantJSON))
            value["birthday_contact_identifier"] = optional(event.birthdayContactIdentifier)
            summary = .init(type: "calendar", title: event.title ?? "", startDate: event.startDate,
                endDate: event.endDate, location: event.location, notes: event.notes,
                identifier: event.calendarItemIdentifier, calendarID: event.calendar?.calendarIdentifier,
                occurrenceDate: event.occurrenceDate)
        } else if let reminder = item as? EKReminder {
            value["type"] = "reminder"; value["priority"] = reminder.priority
            value["is_completed"] = reminder.isCompleted
            value["completion_date"] = optional(reminder.completionDate.map(iso))
            value["start_components"] = optional(reminder.startDateComponents.map(componentsJSON))
            value["due_components"] = optional(reminder.dueDateComponents.map(componentsJSON))
            value["due_date"] = optional(reminder.dueDateComponents?.date.map(iso))
            summary = .init(type: "reminder", title: reminder.title ?? "",
                dueDate: reminder.dueDateComponents?.date, location: reminder.location,
                notes: reminder.notes, priority: reminder.priority, completed: reminder.isCompleted,
                identifier: reminder.calendarItemIdentifier, calendarID: reminder.calendar?.calendarIdentifier)
        } else {
            summary = .init(type: "unknown", title: item.title ?? "", identifier: item.calendarItemIdentifier)
        }
        return .init(json: json(value), item: summary)
    }

    nonisolated private static func calendarJSON(_ calendar: EKCalendar) -> [String: Any] {
        var value: [String: Any] = [
            "identifier": calendar.calendarIdentifier, "title": calendar.title,
            "type": calendar.type.rawValue, "allows_content_modifications": calendar.allowsContentModifications,
            "is_subscribed": calendar.isSubscribed, "is_immutable": calendar.isImmutable,
            "allowed_entity_types": calendar.allowedEntityTypes.rawValue,
            "supported_event_availabilities": calendar.supportedEventAvailabilities.rawValue,
            "source": optional(calendar.source.map(sourceJSON))
        ]
        if let color = calendar.cgColor {
            let uiColor = UIColor(cgColor: color)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                value["color"] = String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
            }
        }
        return value
    }

    nonisolated private static func sourceJSON(_ source: EKSource) -> [String: Any] {
        ["identifier": source.sourceIdentifier, "title": source.title,
         "type": source.sourceType.rawValue, "is_delegate": source.isDelegate]
    }

    nonisolated private static func componentsJSON(_ date: DateComponents) -> [String: Any] {
        let values: [String: Int?] = [
            "era": date.era, "year": date.year, "year_for_week_of_year": date.yearForWeekOfYear,
            "quarter": date.quarter, "month": date.month, "week_of_month": date.weekOfMonth,
            "week_of_year": date.weekOfYear, "weekday": date.weekday,
            "weekday_ordinal": date.weekdayOrdinal, "day": date.day,
            "hour": date.hour, "minute": date.minute, "second": date.second, "nanosecond": date.nanosecond
        ]
        var result = values.compactMapValues { $0 }.mapValues { $0 as Any }
        result["time_zone"] = optional(date.timeZone?.identifier)
        return result
    }

    nonisolated private static func locationJSON(_ location: EKStructuredLocation) -> [String: Any] {
        ["title": optional(location.title), "latitude": optional(location.geoLocation?.coordinate.latitude),
         "longitude": optional(location.geoLocation?.coordinate.longitude), "radius": location.radius]
    }

    nonisolated private static func alarmJSON(_ alarm: EKAlarm) -> [String: Any] {
        ["absolute_date": optional(alarm.absoluteDate.map(iso)), "relative_offset": alarm.relativeOffset,
         "proximity": alarm.proximity.rawValue, "structured_location": optional(alarm.structuredLocation.map(locationJSON))]
    }

    nonisolated private static func ruleJSON(_ rule: EKRecurrenceRule) -> [String: Any] {
        var value: [String: Any] = [
            "frequency": rule.frequency.rawValue, "interval": rule.interval,
            "first_day_of_week": rule.firstDayOfTheWeek, "calendar_identifier": rule.calendarIdentifier,
            "days_of_week": (rule.daysOfTheWeek ?? []).map { ["day": $0.dayOfTheWeek.rawValue, "week": $0.weekNumber] },
            "days_of_month": rule.daysOfTheMonth ?? [], "months_of_year": rule.monthsOfTheYear ?? [],
            "weeks_of_year": rule.weeksOfTheYear ?? [], "days_of_year": rule.daysOfTheYear ?? [],
            "set_positions": rule.setPositions ?? []
        ]
        if let end = rule.recurrenceEnd {
            value["end_date"] = optional(end.endDate.map(iso))
            value["occurrence_count"] = end.occurrenceCount
        }
        return value
    }

    nonisolated private static func participantJSON(_ participant: EKParticipant) -> [String: Any] {
        ["name": optional(participant.name), "url": participant.url.absoluteString,
         "status": participant.participantStatus.rawValue, "role": participant.participantRole.rawValue,
         "type": participant.participantType.rawValue, "is_current_user": participant.isCurrentUser]
    }

    nonisolated private static func matchesKeyword(_ item: EKCalendarItem, _ keyword: String?) -> Bool {
        guard let keyword, !keyword.isEmpty else { return true }
        return (item.title ?? "").localizedCaseInsensitiveContains(keyword) ||
            (item.notes ?? "").localizedCaseInsensitiveContains(keyword) ||
            (item.location ?? "").localizedCaseInsensitiveContains(keyword)
    }

    nonisolated private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    nonisolated private static func optional(_ value: Any?) -> Any { value ?? NSNull() }
    nonisolated private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return text
    }
    nonisolated private static func parsedJSON(_ value: String) -> Any {
        (try? JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])) ?? NSNull()
    }

    private func operationResult(_ request: HanlinCalendarOperationRequest, committed: Bool = false,
                                 data: Any, items: [HanlinSystemEvent] = []) -> HanlinCalendarOperationResult {
        let receipt: [String: Any] = ["status": "succeeded", "operation": request.operation.rawValue,
            "committed": committed, "verification": committed ? "EventKit save completed" : "EventKit read completed",
            "data": data]
        return .init(operation: request.operation, committed: committed, modelText: Self.json(receipt), items: items)
    }
}
#endif
