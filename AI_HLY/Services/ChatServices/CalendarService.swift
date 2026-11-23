import Foundation
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

private func appEvent(_ event: HanlinSystemEvent) -> EventItem {
    EventItem(type: event.type, title: event.title, startDate: event.startDate, endDate: event.endDate,
        dueDate: event.dueDate, location: event.location, notes: event.notes, priority: event.priority,
        completed: event.completed, calendarIdentifier: event.identifier)
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
