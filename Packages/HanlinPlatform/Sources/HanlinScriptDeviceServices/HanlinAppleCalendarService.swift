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
}
#endif
