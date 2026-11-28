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

@MainActor
@Suite("Calendar operation dispatch and receipts")
struct CalendarOperationToolTests {
    @Test
    func noteUpdateDispatchesExistingIDAndEmitsSavedCard() async throws {
        let container = try ModelContainer(for: ToolKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let api = APIManager(context: container.mainContext)
        var dispatches = 0
        let result = await api.executeLegacyTool(name: "manage_calendar",
            argumentsJSON: #"{"operation":"update_reminder","identifier":"existing-reminder","item":{"notes":"Trip to parents"}}"#,
            context: .init(localeIdentifier: "he"), continuation: nil,
            calendarOperationProvider: { request in
                dispatches += 1
                #expect(request.operation == .updateReminder && request.identifier == "existing-reminder")
                #expect(request.item?.notes == "Trip to parents" && request.item?.title == nil)
                return .init(operation: .updateReminder, committed: true,
                    modelText: #"{"status":"succeeded","operation":"update_reminder","committed":true,"identifier":"existing-reminder","notes":"Trip to parents"}"#,
                    items: [.init(type: "reminder", title: "Candles", notes: "Trip to parents", identifier: "existing-reminder")])
            })
        #expect(dispatches == 1 && result.outcome == .succeeded && !result.isError)
        #expect(result.hasLegacyPresentationPayload)
        #expect(api.events?.count == 1 && api.events?.first?.resolvedItemIdentifier == "existing-reminder")
        #expect(result.modelText.contains("\"committed\":true"))
    }

    @Test
    func updateWithoutIDNeverDispatchesAndCannotCreateReplacement() async throws {
        let container = try ModelContainer(for: ToolKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let api = APIManager(context: container.mainContext)
        var dispatches = 0
        let result = await api.executeLegacyTool(name: "manage_calendar",
            argumentsJSON: #"{"operation":"update_reminder","item":{"notes":"Changed"}}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarOperationProvider: { _ in
                dispatches += 1
                return .init(operation: .updateReminder, committed: true, modelText: "unexpected")
            })
        #expect(dispatches == 0 && result.outcome == .invalidArguments && result.isError)
        #expect(api.events == nil && !result.hasLegacyPresentationPayload)
    }

    @Test
    func failedUpdateHasNoSuccessCardOrCommittedReceipt() async throws {
        let container = try ModelContainer(for: ToolKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let api = APIManager(context: container.mainContext)
        let result = await api.executeLegacyTool(name: "manage_calendar",
            argumentsJSON: #"{"operation":"update_reminder","identifier":"missing","item":{"notes":"Changed"}}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            calendarOperationProvider: { _ in throw HanlinAppleDeviceServiceError.denied(.reminders) })
        #expect(result.outcome == .rejectedByCapability && result.isError)
        #expect(api.events == nil && !result.hasLegacyPresentationPayload)
        #expect(!result.modelText.contains("\"committed\":true"))
    }

    @Test
    func legacyItemIdentifierSurvivesHistoryDecoding() throws {
        let item = try JSONDecoder().decode(EventItem.self,
            from: Data(#"{"type":"reminder","title":"Old item","calendarIdentifier":"real-item-id"}"#.utf8))
        #expect(item.resolvedItemIdentifier == "real-item-id")
        #expect(item.calendarID == nil)
        let reread = try JSONDecoder().decode(EventItem.self, from: JSONEncoder().encode(item))
        #expect(reread.resolvedItemIdentifier == "real-item-id")
    }

    @Test
    func calendarSchemaAndSkillExposeOperationsAndReceiptRules() throws {
        let function = try #require(calendarOperationToolSchema()["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        let operation = try #require(properties["operation"] as? [String: Any])
        #expect(Set(try #require(operation["enum"] as? [String])) == Set(HanlinCalendarOperation.allCases.map(\.rawValue)))
        let sources = LegacyToolCanonicalAdapter.sources()
        let tool = try #require(sources.first(where: { $0.toolName == "manage_calendar" }))
        #expect(tool.descriptor.risk == .write)
        #expect(tool.descriptor.approvalPolicy.actionParameter == "operation")
        #expect(tool.descriptor.approvalPolicy.nonSensitiveActions == ["authorization_status"])
    }
}

#if targetEnvironment(simulator)
@MainActor
@Suite("Native saved calendar item regression")
struct CalendarNativeMutationTests {
    @Test
    func updateReminderNotesPreservesIdentityAndEndDaySearchFindsIt() async throws {
        let store = EKEventStore()
        try #require(EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
                     "Run the existing calendar simulator permission preparation first.")
        let service = HanlinAppleCalendarService(store: store)
        let title = "Hanlin owned note regression " + UUID().uuidString
        func request(_ payload: [String: Any]) throws -> HanlinCalendarOperationRequest {
            let data = try JSONSerialization.data(withJSONObject: payload)
            return try .decode(String(decoding: data, as: UTF8.self))
        }
        let create = try await service.execute(request([
            "operation": "create_reminder",
            "item": ["title": title, "due_date": "2026-11-27T15:30:00+02:00", "notes": "Original"]
        ]))
        let id = try #require(create.items.first?.identifier)
        defer {
            if let remaining = store.calendarItem(withIdentifier: id) as? EKReminder {
                do { try store.remove(remaining, commit: true) }
                catch { Issue.record("Could not remove the owned reminder fixture: \(error)") }
            }
        }
        let update = try await service.execute(request([
            "operation": "update_reminder", "identifier": id, "item": ["notes": "Trip to parents"]
        ]))
        #expect(update.committed && update.items.first?.identifier == id)
        let saved = try #require(store.calendarItem(withIdentifier: id) as? EKReminder)
        #expect(saved.title == title && saved.notes == "Trip to parents")
        let search = try await service.execute(request([
            "operation": "list_reminders", "start_date": "2026-11-27", "end_date": "2026-11-27", "keyword": title
        ]))
        let result = try #require(try JSONSerialization.jsonObject(with: Data(search.modelText.utf8)) as? [String: Any])
        let data = try #require(result["data"] as? [String: Any])
        #expect(data["total_count"] as? Int == 1)
        _ = try await service.execute(request(["operation": "complete_reminder", "identifier": id]))
        #expect((store.calendarItem(withIdentifier: id) as? EKReminder)?.isCompleted == true)
        _ = try await service.execute(request(["operation": "reopen_reminder", "identifier": id]))
        #expect((store.calendarItem(withIdentifier: id) as? EKReminder)?.isCompleted == false)
        _ = try await service.execute(request(["operation": "delete_reminder", "identifier": id]))
        #expect(store.calendarItem(withIdentifier: id) == nil)
    }

    @Test
    func eventNotePatchPreservesAlarmAndRecurrence() async throws {
        let store = EKEventStore()
        try #require(EKEventStore.authorizationStatus(for: .event) == .fullAccess,
                     "Run the existing calendar simulator permission preparation first.")
        let service = HanlinAppleCalendarService(store: store)
        let title = "Hanlin owned event regression " + UUID().uuidString
        func request(_ payload: [String: Any]) throws -> HanlinCalendarOperationRequest {
            try .decode(String(decoding: JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
        }
        let create = try await service.execute(request([
            "operation": "create_event", "item": ["title": title,
                "start_date": "2027-01-08T15:00:00+02:00", "end_date": "2027-01-08T16:00:00+02:00",
                "alarms": [["relative_offset": -900]],
                "recurrence_rules": [["frequency": "weekly", "occurrence_count": 3]]]
        ]))
        let id = try #require(create.items.first?.identifier)
        defer {
            if let event = store.calendarItem(withIdentifier: id) as? EKEvent {
                do { try store.remove(event, span: .futureEvents, commit: true) }
                catch { Issue.record("Could not remove the owned event fixture: \(error)") }
            }
        }
        let update = try await service.execute(request([
            "operation": "update_event", "identifier": id, "span": "future_events",
            "occurrence_date": "2027-01-08T15:00:00+02:00", "item": ["notes": "Saved note"]
        ]))
        #expect(update.committed)
        let saved = try await service.eventForPresentation(identifier: try #require(update.items.first?.identifier))
        #expect(saved.title == title && saved.notes == "Saved note")
        #expect(saved.alarms?.first?.relativeOffset == -900)
        #expect(saved.recurrenceRules?.first?.frequency == .weekly)
    }
}
#endif
