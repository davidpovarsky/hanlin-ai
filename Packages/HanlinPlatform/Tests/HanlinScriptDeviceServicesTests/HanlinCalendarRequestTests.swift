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
