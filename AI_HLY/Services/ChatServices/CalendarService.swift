import Foundation
import EventKit
import HanlinScriptDeviceServices

// Keep the original application values at this seam. EventKit execution, request
// validation and cancellation live in the shared SDK rather than a second engine.
@MainActor
private enum HanlinAppCalendarProvider {
    static let service = HanlinAppleCalendarService()
}

@MainActor
func searchSystemEvents(_ request: HanlinCalendarSearchRequest) async throws -> [EventItem] {
    try await HanlinAppCalendarProvider.service.search(request).map(appEvent)
}

@MainActor
func writeSystemEvent(_ request: HanlinCalendarWriteRequest) async throws -> EventItem {
    appEvent(try await HanlinAppCalendarProvider.service.write(request))
}

func appEvent(_ event: HanlinSystemEvent) -> EventItem {
    EventItem(type: event.type, title: event.title, startDate: event.startDate, endDate: event.endDate,
        dueDate: event.dueDate, location: event.location, notes: event.notes, priority: event.priority,
        completed: event.completed, calendarIdentifier: event.identifier, itemIdentifier: event.identifier,
        calendarID: event.calendarID, occurrenceDate: event.occurrenceDate)
}

func calendarToolFailure(_ error: any Error) -> (outcome: NativeToolExecutionOutcome, message: String) {
    if error is CancellationError {
        return (.cancelled, "The calendar request was cancelled.")
    }
    if let error = error as? HanlinCalendarRequestError {
        return (error == .timedOut ? .timedOut : .invalidArguments, error.localizedDescription)
    }
    if let error = error as? HanlinAppleDeviceServiceError {
        switch error {
        case .denied:
            return (.rejectedByCapability, "Calendar or Reminders access was not granted.")
        case .unavailable, .unsupportedByPlatform:
            return (.rejectedByAvailability, "The requested calendar or reminders service is unavailable.")
        case .invalidRequest(let field):
            return (.invalidArguments, "The calendar request is invalid: \(field).")
        case .noData:
            return (.failed, "The calendar service could not return the requested data.")
        }
    }
    return (.failed, "The calendar operation failed. No successful result was received.")
}

@MainActor
func manageSystemCalendar(_ request: HanlinCalendarOperationRequest) async throws -> HanlinCalendarOperationResult {
    try await HanlinAppCalendarProvider.service.execute(request)
}

@MainActor
func calendarEventForPresentation(_ item: EventItem) async throws -> EKEvent {
    guard let identifier = item.resolvedItemIdentifier, !identifier.isEmpty else {
        throw HanlinCalendarRequestError.invalidField("saved item identifier is missing")
    }
    return try await HanlinAppCalendarProvider.service.eventForPresentation(
        identifier: identifier, occurrenceDate: item.occurrenceDate ?? item.startDate)
}

@MainActor
func reminderForPresentation(_ item: EventItem) async throws -> HanlinScriptReminderItem? {
    guard let identifier = item.resolvedItemIdentifier, !identifier.isEmpty else {
        throw HanlinCalendarRequestError.invalidField("saved item identifier is missing")
    }
    return try await HanlinAppCalendarProvider.service.reminder(identifier: identifier)
}

/// A model-facing receipt carries the actual saved item ID and notes. A separate
/// memory write can never be mistaken for this operation's completion.
func calendarSavedReceipt(_ item: EventItem, operation: String) -> String {
    let formatter = ISO8601DateFormatter()
    var data: [String: Any] = [
        "status": "succeeded", "operation": operation, "committed": true,
        "identifier": item.resolvedItemIdentifier ?? "",
        "type": item.type, "title": item.title
    ]
    if let notes = item.notes { data["notes"] = notes }
    if let date = item.startDate { data["start_date"] = formatter.string(from: date) }
    if let date = item.endDate { data["end_date"] = formatter.string(from: date) }
    if let date = item.dueDate { data["due_date"] = formatter.string(from: date) }
    if let id = item.calendarID { data["calendar_identifier"] = id }
    if let date = item.occurrenceDate { data["occurrence_date"] = formatter.string(from: date) }
    guard let json = try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys),
          let text = String(data: json, encoding: .utf8) else {
        return "EventKit committed the requested creation. Do not repeat it; the result could not be formatted."
    }
    return text
}
