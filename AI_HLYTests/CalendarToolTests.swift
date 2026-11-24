import Foundation
import HanlinScriptDeviceServices
import SwiftData
import Testing
@testable import AI_Hanlin

// Exercise the actual original dispatcher with a deterministic EventKit boundary.
// Device authorization and the user's reported physical crash remain separate gates.
@MainActor
@Suite("Calendar tools recover after failure")
struct CalendarToolTests {
    @Test
    func reversedDatesDoNotDispatchAndNextSearchCanComplete() async throws {
        let container = try database()
        let api = APIManager(context: container.mainContext)
        var dispatches = 0
        let invalid = await api.executeLegacyTool(name: "search_calendar_and_reminders",
            argumentsJSON: #"{"start_date":"2026-12-23","end_date":"2026-11-23","event_type":"calendar"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarSearchProvider: { _ in dispatches += 1; return [] })
        #expect(invalid.outcome == .invalidArguments && invalid.isError)
        #expect(dispatches == 0)
        let valid = await api.executeLegacyTool(name: "search_calendar_and_reminders",
            argumentsJSON: #"{"start_date":"2026-11-23","end_date":"2026-11-24","event_type":"calendar"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarSearchProvider: { request in
                dispatches += 1
                #expect(request.searchesCalendar && !request.searchesReminders)
                return [event()]
            })
        #expect(valid.outcome == .succeeded && !valid.isError)
        #expect(dispatches == 1)
        #expect(valid.modelText.contains("Meeting"))
    }

    @Test(arguments: ["denied", "timeout", "cancelled"])
    func failedReadProducesStructuredOutcomeWithoutPoisoningNextCall(kind: String) async throws {
        let container = try database()
        let api = APIManager(context: container.mainContext)
        let result = await api.executeLegacyTool(name: "search_calendar_and_reminders",
            argumentsJSON: #"{"keyword":"Meeting","event_type":"reminder"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarSearchProvider: { _ in
                switch kind {
                case "denied": throw HanlinAppleDeviceServiceError.denied(.reminders)
                case "timeout": throw HanlinCalendarRequestError.timedOut
                default: throw CancellationError()
                }
            })
        let expected: NativeToolExecutionOutcome = kind == "denied" ? .rejectedByCapability :
            kind == "timeout" ? .timedOut : .cancelled
        #expect(result.outcome == expected && result.isError)
        #expect(result.diagnostics.backendRoute == "system:eventkit")
        #expect(result.diagnostics.failureCategory == expected.rawValue)
        #expect(result.diagnostics.wasCancelled == (kind == "cancelled"))
        #expect(result.diagnostics.didTimeOut == (kind == "timeout"))
        #expect(!result.hasLegacyPresentationPayload)
        let next = await api.executeLegacyTool(name: "search_calendar_and_reminders",
            argumentsJSON: #"{"keyword":"Meeting","event_type":"calendar"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarSearchProvider: { _ in [event()] })
        #expect(next.outcome == .succeeded && next.modelText.contains("Meeting"))
    }

    @Test
    func malformedWriteIsRejectedBeforeExecutorAndCommittedWriteIsRetained() async throws {
        let container = try database()
        let api = APIManager(context: container.mainContext)
        var dispatches = 0
        let invalid = await api.executeLegacyTool(name: "write_system_event",
            argumentsJSON: #"{"type":"calendar","title":"Meeting","start_date":"not-a-date","end_date":"2026-11-23T12:00:00Z"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarWriteProvider: { _ in dispatches += 1; return event() })
        #expect(invalid.outcome == .invalidArguments && invalid.isError)
        #expect(dispatches == 0 && api.events == nil)
        let valid = await api.executeLegacyTool(name: "write_system_event",
            argumentsJSON: #"{"type":"calendar","title":"Meeting","start_date":"2026-11-23T11:00:00Z","end_date":"2026-11-23T12:00:00Z"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarWriteProvider: { _ in dispatches += 1; return event() })
        #expect(valid.outcome == .succeeded && !valid.isError)
        #expect(dispatches == 1 && api.events?.count == 1)
        #expect(valid.hasLegacyPresentationPayload)
    }

    @Test
    func failedWriteIsNeverReportedAsCommitted() async throws {
        let container = try database()
        let api = APIManager(context: container.mainContext)
        let result = await api.executeLegacyTool(name: "write_system_event",
            argumentsJSON: #"{"type":"reminder","title":"Meeting"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarWriteProvider: { _ in throw HanlinAppleDeviceServiceError.unavailable(.reminders) })
        #expect(result.outcome == .rejectedByAvailability && result.isError)
        #expect(api.events == nil)
        #expect(!result.hasLegacyPresentationPayload)
    }

    private func event() -> EventItem {
        .init(type: "calendar", title: "Meeting", startDate: Date(timeIntervalSince1970: 100),
            endDate: Date(timeIntervalSince1970: 200), dueDate: nil, location: nil, notes: nil,
            priority: nil, completed: nil, calendarIdentifier: "calendar-test-item")
    }

    private func database() throws -> ModelContainer {
        try ModelContainer(for: ToolKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

#if targetEnvironment(simulator)
import EventKit

/// Owned native records only, in the fresh CI simulator granted by
/// prepare_calendar_acceptance.py. No EventKit implementation is substituted.
@MainActor
final class HanlinEventKitAcceptanceFixture {
    let store = EKEventStore()
    let marker = "Hanlin EventKit acceptance " + UUID().uuidString
    private(set) var titles: [String] = []
    private var events: [EKEvent] = []
    private var reminder: EKReminder?

    init() throws {
        #expect(EKEventStore.authorizationStatus(for: .event) == .fullAccess)
        #expect(EKEventStore.authorizationStatus(for: .reminder) == .fullAccess)
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw NSError(domain: "HanlinNativeCalendarAcceptance", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Native acceptance requires calendar and reminder grants"])
        }
        do {
            let calendar = try #require(store.defaultCalendarForNewEvents,
                "The owned simulator must expose its real default calendar")
            let reminderCalendar = try #require(store.defaultCalendarForNewReminders(),
                "The owned simulator must expose its real default reminder calendar")
            for offset in [-4, 0, 4] {
                let event = EKEvent(eventStore: store)
                event.title = marker + " year " + String(offset)
                event.startDate = try #require(Calendar.current.date(byAdding: .year, value: offset, to: .now))
                event.endDate = event.startDate.addingTimeInterval(1800)
                event.calendar = calendar
                try store.save(event, span: .thisEvent)
                events.append(event)
                titles.append(event.title)
            }
            let item = EKReminder(eventStore: store)
            item.title = marker + " reminder"
            item.calendar = reminderCalendar
            item.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            try store.save(item, commit: true)
            reminder = item
            titles.append(item.title)
        } catch {
            removeOwnedItems()
            throw error
        }
    }

    func removeOwnedItems() {
        for event in events {
            do { try store.remove(event, span: .thisEvent) }
            catch { Issue.record("Failed to remove this fixture's native event: \(error)") }
        }
        events.removeAll()
        if let reminder {
            do { try store.remove(reminder, commit: true) }
            catch { Issue.record("Failed to remove this fixture's native reminder: \(error)") }
        }
        reminder = nil
    }
}
#endif
