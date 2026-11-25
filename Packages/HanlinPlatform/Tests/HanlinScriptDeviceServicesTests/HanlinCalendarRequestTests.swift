import Foundation
import Testing
@testable import HanlinScriptDeviceServices

@Suite("Shared calendar requests")
struct HanlinCalendarRequestTests {
    @Test
    func reversedRangeFailsBeforeDateInterval() throws {
        let start = try #require(try HanlinCalendarDateParser.day("2026-12-23", field: "start"))
        let end = try #require(try HanlinCalendarDateParser.day("2026-11-23", field: "end"))
        #expect(throws: HanlinCalendarRequestError.invalidDateRange) {
            try HanlinCalendarSearchRequest(startDate: start, endDate: end)
        }
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity])
    func nonfiniteDatesCannotReachEventKit(value: Double) {
        #expect(throws: HanlinCalendarRequestError.invalidDate("start")) {
            try HanlinCalendarSearchRequest(startDate: Date(timeIntervalSinceReferenceDate: value))
        }
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "2026-11-23tail", "2026-11-23T00:00:00Z"])
    func suppliedMalformedDayDoesNotBecomeUnbounded(value: String) {
        #expect(throws: HanlinCalendarRequestError.invalidDate("start_date")) {
            try HanlinCalendarDateParser.day(value, field: "start_date")
        }
    }

    @Test
    func singleEndpointOutsideDefaultWindowKeepsOrderedBounds() throws {
        let now = try #require(try HanlinCalendarDateParser.day("2026-11-23", field: "now"))
        let future = try #require(try HanlinCalendarDateParser.day("2050-01-01", field: "future"))
        let past = try #require(try HanlinCalendarDateParser.day("1900-01-01", field: "past"))
        let forward = try HanlinCalendarSearchRequest(startDate: future).calendarInterval(now: now)
        let backward = try HanlinCalendarSearchRequest(endDate: past).calendarInterval(now: now)
        #expect(forward.duration > 0 && forward.contains(future))
        #expect(backward.duration > 0 && backward.contains(past))
    }

    @Test
    func broadSearchRetainsPresentAndFutureInsteadOfEventKitTruncation() throws {
        let now = try #require(try HanlinCalendarDateParser.day("2026-11-23", field: "now"))
        let request = try HanlinCalendarSearchRequest(keyword: "Meeting", eventType: "calendar")
        let range = try request.calendarInterval(now: now)
        let slices = try HanlinCalendarDateParser.eventIntervals(start: range.start, end: range.end)
        #expect(slices.count > 1)
        #expect(slices.first?.start == range.start && slices.last?.end == range.end)
        #expect(slices.allSatisfy { $0.duration < 4 * 365 * 24 * 60 * 60 })
        #expect(slices.contains { $0.contains(now) })
        #expect(slices.contains { $0.contains(now.addingTimeInterval(365 * 24 * 60 * 60)) })
        for index in 1..<slices.count { #expect(slices[index - 1].end == slices[index].start) }
    }

    @Test
    func validReminderKeepsOriginalAlarmAndPriority() throws {
        let due = try #require(try HanlinCalendarDateParser.timestamp("2026-11-23T12:30:00.250+02:00", field: "due"))
        let request = try HanlinCalendarWriteRequest(type: "reminder", title: "Meeting",
            dueDate: due, priority: 5, reminderMinutes: 10)
        #expect(request.reminderOffset == -600)
        #expect(request.reminderAbsoluteDate == nil)
        #expect(request.dueDate == due && request.priority == 5)
    }

    @Test
    func hugeAlarmCannotOverflowIntegerOrCreateInvalidEventKitDate() {
        #expect(throws: HanlinCalendarRequestError.invalidReminderOffset) {
            try HanlinCalendarWriteRequest(type: "reminder", title: "Meeting", reminderMinutes: Int.max)
        }
    }

    @Test
    func incompleteCalendarCannotReachWrite() {
        #expect(throws: HanlinCalendarRequestError.missingCalendarDates) {
            try HanlinCalendarWriteRequest(type: "calendar", title: "Meeting")
        }
        #expect(throws: HanlinCalendarRequestError.invalidPriority) {
            try HanlinCalendarWriteRequest(type: "reminder", title: "Meeting", priority: 10)
        }
    }

    @Test
    func requestedEntitySelectionIsPreserved() throws {
        let calendar = try HanlinCalendarSearchRequest(keyword: "Meeting", eventType: " calendar ")
        #expect(calendar.searchesCalendar && !calendar.searchesReminders)
        let reminders = try HanlinCalendarSearchRequest(keyword: "Meeting", eventType: "REMINDER")
        #expect(!reminders.searchesCalendar && reminders.searchesReminders)
    }
}

@MainActor
@Suite("Calendar callback lifetime")
struct HanlinCalendarCallbackOperationTests {
    @Test
    func cancelledFetchFinishesWithoutOSCallbackAndIgnoresLateResult() async {
        var cancellationCount = 0
        var callback: (@Sendable (Result<Int, any Error>) -> Void)?
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await HanlinCalendarCallbackOperation<Int>().value { completion in
                callback = completion
                startedContinuation.yield()
                startedContinuation.finish()
                return { cancellationCount += 1 }
            }
        }
        for await _ in started { break }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled fetch returned success")
        } catch { #expect(error is CancellationError) }
        #expect(cancellationCount == 1)
        callback?(.success(99))
        callback?(.failure(HanlinCalendarRequestError.timedOut))
        await Task.yield()
        #expect(cancellationCount == 1)
    }

    @Test
    func missingOSCallbackTimesOutAndNextOperationWorks() async throws {
        var cancellationCount = 0
        do {
            _ = try await HanlinCalendarCallbackOperation<Int>().value(timeout: .milliseconds(5)) { _ in
                { cancellationCount += 1 }
            }
            Issue.record("Missing callback did not time out")
        } catch { #expect(error as? HanlinCalendarRequestError == .timedOut) }
        #expect(cancellationCount == 1)
        let result = try await HanlinCalendarCallbackOperation<Int>().value { completion in
            completion(.success(42))
            return nil
        }
        #expect(result == 42)
    }

    @Test
    func completionIsConsumedOnceWithoutCancellingSuccessfulRequest() async throws {
        var cancellationCount = 0
        let result = try await HanlinCalendarCallbackOperation<Int>().value { completion in
            completion(.success(42))
            completion(.success(99))
            return { cancellationCount += 1 }
        }
        #expect(result == 42)
        await Task.yield()
        #expect(cancellationCount == 0)
    }

    @Test
    func alreadyCancelledOperationNeverStartsEventKit() async {
        var didStart = false
        let task = Task {
            do {
                _ = try await HanlinCalendarCallbackOperation<Int>().value { completion in
                    didStart = true
                    completion(.success(42))
                    return nil
                }
                Issue.record("Already cancelled operation succeeded")
            } catch { #expect(error is CancellationError) }
        }
        task.cancel()
        await task.value
        #expect(!didStart)
    }
}

@Suite("Calendar operation contracts")
struct HanlinCalendarOperationRequestTests {
    @Test
    func reminderEndDayIncludesAfternoonAndExcludesFollowingMidnight() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Jerusalem"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = try #require(try HanlinCalendarDateParser.day("2026-11-25", field: "start", timeZone: zone))
        let end = try #require(try HanlinCalendarDateParser.day("2026-11-27", field: "end", timeZone: zone))
        let request = try HanlinCalendarSearchRequest(startDate: start, endDate: end, eventType: "reminder")
        let afternoon = try #require(try HanlinCalendarDateParser.timestamp("2026-11-27T15:30:00+02:00", field: "due"))
        let nextDay = try #require(try HanlinCalendarDateParser.timestamp("2026-11-28T00:00:00+02:00", field: "due"))
        let previousDay = try #require(try HanlinCalendarDateParser.timestamp("2026-11-24T23:59:00+02:00", field: "due"))
        #expect(request.matchesDate(afternoon, calendar: calendar))
        #expect(!request.matchesDate(nextDay, calendar: calendar))
        #expect(!request.matchesDate(previousDay, calendar: calendar))
        #expect(try request.calendarInterval(calendar: calendar).start == start)
    }

    @Test
    func inclusiveDayRangeUsesCalendarArithmeticAcrossDST() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let request = try HanlinCalendarOperationRequest.decode(#"{"operation":"list_events","start_date":"2026-03-08","end_date":"2026-03-08"}"#)
        let bounds = try request.queryBounds(timeZone: zone)
        let start = try #require(bounds.start)
        let end = try #require(bounds.end)
        #expect(end.timeIntervalSince(start) == 23 * 60 * 60)
    }

    @Test(arguments: ["update_event", "delete_event", "update_reminder", "delete_reminder", "complete_reminder", "reopen_reminder"])
    func mutationRequiresAnActualIdentifier(operation: String) {
        let json = "{\"operation\":\"\(operation)\",\"item\":{\"notes\":\"changed\"}}"
        #expect(throws: HanlinCalendarRequestError.self) { try HanlinCalendarOperationRequest.decode(json) }
    }

    @Test
    func patchKeepsOmittedFieldsAndExplicitClearDistinct() throws {
        let patch = try HanlinCalendarOperationRequest.decode(#"{"operation":"update_reminder","identifier":"saved-id","item":{"notes":"trip home"}} "#)
        #expect(patch.identifier == "saved-id")
        #expect(patch.item?.notes == "trip home")
        #expect(patch.item?.title == nil && patch.item?.alarms == nil && patch.item?.recurrenceRules == nil)
        let cleared = try HanlinCalendarOperationRequest.decode(#"{"operation":"update_reminder","identifier":"saved-id","item":{"clear_fields":["notes"]}}"#)
        #expect(cleared.item?.notes == nil && cleared.item?.clearFields == ["notes"])
        #expect(throws: HanlinCalendarRequestError.self) {
            try HanlinCalendarOperationRequest.decode(#"{"operation":"update_reminder","identifier":"saved-id","item":{"notes":"keep","clear_fields":["notes"]}}"#)
        }
    }

    @Test
    func dueTimestampCannotBeSetWhileClearingDueComponents() throws {
        #expect(throws: HanlinCalendarRequestError.invalidField("cannot set and clear due_date/due_components")) {
            try HanlinCalendarOperationRequest.decode(#"{"operation":"update_reminder","identifier":"saved-id","item":{"due_date":"2026-11-27T15:30:00+02:00","clear_fields":["due_components"]}}"#)
        }
        let valid = try HanlinCalendarOperationRequest.decode(#"{"operation":"update_reminder","identifier":"saved-id","item":{"due_date":"2026-11-27T15:30:00+02:00"}}"#)
        #expect(valid.item?.dueDate == "2026-11-27T15:30:00+02:00")
    }

    @Test
    func dueComponentsCannotBeSetWhileClearingDueTimestamp() throws {
        #expect(throws: HanlinCalendarRequestError.invalidField("cannot set and clear due_date/due_components")) {
            try HanlinCalendarOperationRequest.decode(#"{"operation":"update_reminder","identifier":"saved-id","item":{"due_components":{"year":2026,"month":11,"day":27,"hour":15,"minute":30},"clear_fields":["due_date"]}}"#)
        }
        let valid = try HanlinCalendarOperationRequest.decode(#"{"operation":"update_reminder","identifier":"saved-id","item":{"clear_fields":["due_date"]}}"#)
        #expect(valid.item?.clearFields == ["due_date"])
    }

    @Test(arguments: [
        #"{"operation":"update_event","identifier":"saved-id","item":{}}"#,
        #"{"operation":"update_reminder","identifier":"saved-id","item":{}}"#,
        #"{"operation":"update_event","identifier":"saved-id","item":{"clear_fields":[]}}"#,
        #"{"operation":"update_reminder","identifier":"saved-id","item":{"clear_fields":[]}}"#,
        #"{"operation":"update_calendar","entity_type":"event","identifier":"saved-id","calendar":{}}"#,
        #"{"operation":"update_calendar","entity_type":"event","identifier":"saved-id","calendar":{"title":null}}"#,
        #"{"operation":"update_calendar","entity_type":"reminder","identifier":"saved-id","calendar":{"color":null}}"#,
        #"{"operation":"update_calendar","entity_type":"event","identifier":"saved-id","calendar":{"source_identifier":null}}"#,
        #"{"operation":"update_calendar","entity_type":"event","identifier":"saved-id","calendar":{"title":"New title","color":null}}"#
    ])
    func emptyMutationAndNullCalendarFieldsAreRejected(json: String) {
        #expect(throws: HanlinCalendarRequestError.self) {
            try HanlinCalendarOperationRequest.decode(json)
        }
    }

    @Test(arguments: ["update_event", "update_reminder"])
    func clearOnlyUpdateStillExpressesAMutation(operation: String) throws {
        let json = "{\"operation\":\"\(operation)\",\"identifier\":\"saved-id\",\"item\":{\"clear_fields\":[\"notes\"]}}"
        let request = try HanlinCalendarOperationRequest.decode(json)
        #expect(request.item?.clearFields == ["notes"] && request.item?.notes == nil)
        let emptyArrays = "{\"operation\":\"\(operation)\",\"identifier\":\"saved-id\",\"item\":{\"alarms\":[],\"recurrence_rules\":[]}}"
        let clearedArrays = try HanlinCalendarOperationRequest.decode(emptyArrays)
        #expect(clearedArrays.item?.alarms?.isEmpty == true)
        #expect(clearedArrays.item?.recurrenceRules?.isEmpty == true)
    }

    @Test(arguments: [
        #"{"operation":"update_reminder","identifier":"saved-id","item":{"due_date":""}}"#,
        #"{"operation":"update_reminder","identifier":"saved-id","item":{"due_date":" \t\n "}}"#,
        #"{"operation":"update_reminder","identifier":"saved-id","item":{"completion_date":""}}"#,
        #"{"operation":"update_event","identifier":"saved-id","item":{"start_date":""}}"#,
        #"{"operation":"update_event","identifier":"saved-id","item":{"end_date":" "}}"#,
        #"{"operation":"update_event","identifier":"saved-id","occurrence_date":"","item":{"notes":"Updated"}}"#,
        #"{"operation":"list_events","start_date":"","end_date":"2026-11-27"}"#,
        #"{"operation":"list_reminders","end_date":"          "}"#,
        #"{"operation":"update_event","identifier":"saved-id","item":{"alarms":[{"absolute_date":""}]}}"#,
        #"{"operation":"update_event","identifier":"saved-id","item":{"recurrence_rules":[{"frequency":"weekly","end_date":" "}]}}"#
    ])
    func suppliedBlankOperationDatesAreRejected(json: String) {
        #expect(throws: HanlinCalendarRequestError.self) {
            try HanlinCalendarOperationRequest.decode(json)
        }
    }

    @Test(arguments: [
        #"{"operation":"update_event","identifier":"id","item":{"attendees":["a@example.com"]}}"#,
        #"{"operation":"create_event","item":{"title":"A","start_date":"2026-11-27T15:00:00Z"}}"#,
        #"{"operation":"update_reminder","identifier":"id","item":{"is_all_day":true}}"#,
        #"{"operation":"request_access","entity_type":"reminder","access":"write_only"}"#,
        #"{"operation":"create_calendar","entity_type":"event","calendar":{"title":"A"}}"#,
        #"{"operation":"list_events","start_date":"2026-11-27","end_date":"2026-11-26"}"#,
        #"{"operation":"update_reminder","identifier":"id","item":{"notes":null}}"#
    ])
    func invalidArgumentsCannotReachEventKit(json: String) {
        #expect(throws: HanlinCalendarRequestError.self) { try HanlinCalendarOperationRequest.decode(json) }
    }

    @Test
    func completePublicWritablePayloadDecodes() throws {
        let request = try HanlinCalendarOperationRequest.decode(#"""
        {"operation":"create_event","item":{"title":"Weekly visit","calendar_identifier":"list",
        "start_date":"2026-11-27T15:00:00+02:00","end_date":"2026-11-27T16:00:00+02:00",
        "time_zone":"Asia/Jerusalem","is_all_day":false,"availability":"busy",
        "location":"Home","structured_location":{"title":"Home","latitude":31.7,"longitude":35.2,"radius":100},
        "url":"https://example.com","notes":"Bring notes",
        "alarms":[{"relative_offset":-900},{"absolute_date":"2026-11-27T10:00:00+02:00"}],
        "recurrence_rules":[{"frequency":"weekly","interval":1,"days_of_week":[{"day":6}],"occurrence_count":4}]}}
        """#)
        #expect(request.operation == .createEvent)
        #expect(request.item?.alarms?.count == 2)
        #expect(request.item?.recurrenceRules?.first?.daysOfWeek?.first?.day == 6)
    }

    @Test
    func invalidRecurrenceAndAlarmAreRejected() {
        #expect(throws: HanlinCalendarRequestError.self) {
            try HanlinCalendarOperationRequest.decode(#"{"operation":"update_event","identifier":"id","item":{"recurrence_rules":[{"frequency":"weekly","interval":0}]}}"#)
        }
        #expect(throws: HanlinCalendarRequestError.self) {
            try HanlinCalendarOperationRequest.decode(#"{"operation":"update_reminder","identifier":"id","item":{"alarms":[{"relative_offset":-10,"absolute_date":"2026-11-27T12:00:00Z"}]}}"#)
        }
    }
}
