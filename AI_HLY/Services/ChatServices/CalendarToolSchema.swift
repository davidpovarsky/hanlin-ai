import Foundation
import HanlinScriptDeviceServices

/// One schema for the shared EventKit service. Fields mirror public iOS APIs;
/// attendees, organizer, source properties and server status are returned read-only.
func calendarOperationToolSchema() -> [String: Any] {
    func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }
    func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }
    func array(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
    let integer: [String: Any] = ["type": "integer"]
    let number: [String: Any] = ["type": "number"]
    let boolean: [String: Any] = ["type": "boolean"]
    let timestamp = string("ISO-8601 timestamp with timezone.")
    let location = object([
        "title": string("Location name."),
        "latitude": number, "longitude": number,
        "radius": ["type": "number", "minimum": 0, "description": "Geofence radius in meters; 0 uses the system default."]
    ])
    let alarm = object([
        "relative_offset": ["type": "number", "description": "Seconds relative to item start/due time; negative means before. Supply this OR absolute_date."],
        "absolute_date": timestamp, "structured_location": location,
        "proximity": ["type": "string", "enum": ["none", "enter", "leave"]]
    ])
    let recurrence = object([
        "frequency": ["type": "string", "enum": ["daily", "weekly", "monthly", "yearly"]],
        "interval": ["type": "integer", "minimum": 1, "description": "Repeat every N units; defaults to 1."],
        "days_of_week": array(object([
            "day": ["type": "integer", "minimum": 1, "maximum": 7, "description": "Sunday=1 through Saturday=7."],
            "week": ["type": "integer", "minimum": -53, "maximum": 53, "description": "Ordinal week; 0 means every matching day."]
        ], required: ["day"])),
        "days_of_month": array(integer), "months_of_year": array(integer),
        "weeks_of_year": array(integer), "days_of_year": array(integer), "set_positions": array(integer),
        "end_date": timestamp,
        "occurrence_count": ["type": "integer", "minimum": 1, "description": "End after this many occurrences; supply this OR end_date, or neither for no end."]
    ], required: ["frequency"])
    var componentProperties: [String: Any] = [:]
    for key in ["era", "year", "year_for_week_of_year", "quarter", "month", "week_of_month",
                "week_of_year", "weekday", "weekday_ordinal", "day", "hour", "minute", "second", "nanosecond"] {
        componentProperties[key] = integer
    }
    let components = object(componentProperties)
    let item = object([
        "title": string("Item title. Required for creation; omitted fields stay unchanged when updating."),
        "calendar_identifier": string("Destination event calendar or reminder list ID from list_calendars. Supplying it moves an existing item."),
        "notes": string("Full replacement notes; omit to preserve, use clear_fields to remove."),
        "location": string("Location text."),
        "url": string("Associated URL; this is user content, not an Apple Calendar deep link."),
        "time_zone": string("IANA timezone, for example Asia/Jerusalem. clear_fields makes an event floating."),
        "start_date": timestamp, "end_date": timestamp, "due_date": timestamp,
        "start_components": components, "due_components": components,
        "is_all_day": boolean,
        "priority": ["type": "integer", "minimum": 0, "maximum": 9, "description": "Reminder priority: 0 unset, 1 highest, 9 lowest."],
        "is_completed": boolean, "completion_date": timestamp,
        "availability": ["type": "string", "enum": ["not_supported", "busy", "free", "tentative", "unavailable"]],
        "structured_location": location, "alarms": array(alarm), "recurrence_rules": array(recurrence),
        "clear_fields": array(["type": "string", "enum": [
            "notes", "location", "url", "time_zone", "start_components", "due_components", "due_date",
            "completion_date", "alarms", "recurrence_rules", "structured_location"
        ]])
    ])
    let calendar = object([
        "title": string("Calendar or reminders-list name."),
        "source_identifier": string("Account/source ID. Required for creation; existing calendars cannot change source."),
        "color": string("Calendar color as #RRGGBB.")
    ])
    return ["type": "function", "function": [
        "name": "manage_calendar",
        "description": """
        Access public iOS EventKit capabilities for calendar events and reminder tasks: permissions; accounts/sources; calendar/list creation, editing and deletion; event/reminder search, lookup, creation, update, deletion and moves; completion; recurrence and alarms; external identifiers and refresh.
        For an update or delete, first read the actual item and use its returned identifier. Never create a replacement when asked to update, and never use a memory/MCP entity ID as an EventKit ID.
        Only claim a change after this tool returns status=succeeded and committed=true for that operation. A memory save or successful search does not confirm a calendar change.
        Event create needs title/start_date/end_date. Reminder create needs title and may omit due time. Updates patch supplied item fields and preserve omitted ones. Empty arrays clear alarms/recurrence; clear_fields removes other optional values.
        For a recurring event use occurrence_date from the returned record plus span=this_event or future_events. EventKit attendee/organizer/status/source properties are read-only. Apple Reminders tags, subtasks, assignment, sharing management and invitation sending are not public writable EventKit APIs.
        Each change commits immediately; failed operations do not create a fallback item. Returned data is the saved EventKit record. Read results include local IDs (may change after account resynchronization), external IDs, permissions, supported fields and recurrence/alarm details.
        """,
        "parameters": object([
            "operation": ["type": "string", "enum": HanlinCalendarOperation.allCases.map(\.rawValue)],
            "entity_type": ["type": "string", "enum": ["event", "reminder", "both"],
                "description": "Required for calendar get/default/create/update/delete and permission selection; list defaults to both."],
            "identifier": string("Exact local item/calendar/source identifier returned by a previous read. Required for get/update/delete/complete/reopen."),
            "external_identifier": string("External UID for find_by_external_identifier; may return multiple matches."),
            "occurrence_date": timestamp,
            "calendar_identifiers": array(string("Calendar/list ID used to scope searches.")),
            "source_identifier": string("Filter list_calendars by an account/source."),
            "keyword": string("Case-insensitive title, notes or location search."),
            "start_date": string("Search lower bound: yyyy-MM-dd (local day) or ISO-8601 timestamp. Required for list_events."),
            "end_date": string("Search upper bound: yyyy-MM-dd includes the whole named day; timestamp is exclusive. Required for list_events."),
            "completed": ["type": "boolean", "description": "Reminder filter. true uses completion date bounds; false or omitted uses due-date bounds."],
            "limit": ["type": "integer", "minimum": 1, "maximum": 2000, "description": "Maximum items returned, default 200. Inspect total_count/truncated."],
            "offset": ["type": "integer", "minimum": 0, "description": "Skip this many sorted search matches for pagination; default 0."],
            "access": ["type": "string", "enum": ["full", "write_only"], "description": "request_access only. write_only is valid only for entity_type=event."],
            "span": ["type": "string", "enum": ["this_event", "future_events"], "description": "Event update/delete recurrence scope; default this_event."],
            "item": item, "calendar": calendar
        ], required: ["operation"])
    ]]
}
