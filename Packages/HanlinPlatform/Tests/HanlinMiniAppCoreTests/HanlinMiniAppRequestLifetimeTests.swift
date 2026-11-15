import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import Testing

@Suite("Personal Host action lifetime")
struct HanlinMiniAppRequestLifetimeTests {
    @Test(.timeLimit(.minutes(1)))
    func actualPersonalHostActionOutlivesTheOldFifteenSecondDeadline() async throws {
        let broker = HanlinMiniAppRequestBroker(limits: .personalHost)
        let request = try fixture()
        let nonce = UUID().uuidString
        await broker.register(target: request.target, action: request.action, capability: request.capability) { _ in
            try await Task.sleep(for: .seconds(16))
            return .string(nonce)
        }
        let start = ContinuousClock.now
        let result = try await broker.request(request)
        #expect(result.requestID == request.id && result.value == .string(nonce))
        #expect(ContinuousClock.now - start >= .seconds(16))
    }

    @Test func explicitlyRequestedDeadlinesAndSizeBudgetsAreStillEnforced() async throws {
        #expect(HanlinMiniAppRequestBroker.Limits().timeout == .seconds(15))
        #expect(HanlinMiniAppRequestBroker.Limits.personalHost.timeout == nil)
        #expect(HanlinMiniAppRequestBroker.Limits.personalHost.maximumPayloadBytes == 1_048_576)
        let request = try fixture()
        let timed = HanlinMiniAppRequestBroker(limits: .init(timeout: .milliseconds(10)))
        await timed.register(target: request.target, action: request.action, capability: request.capability) { _ in
            try await Task.sleep(for: .seconds(1)); return .null
        }
        await #expect(throws: HanlinMiniAppRequestError.timedOut) { _ = try await timed.request(request) }
        let bounded = HanlinMiniAppRequestBroker(limits: .init(maximumPayloadBytes: 1, timeout: nil))
        await #expect(throws: HanlinMiniAppRequestError.payloadTooLarge) { _ = try await bounded.request(request) }
    }

    @Test func uncappedRequestCancellationDrainsItsRealHandlerBeforeReportingCancelled() async throws {
        let broker = HanlinMiniAppRequestBroker(limits: .personalHost), request = try fixture()
        let state = State()
        await broker.register(target: request.target, action: request.action, capability: request.capability) { _ in
            await state.start()
            do { try await Task.sleep(for: .seconds(60)) }
            catch { await state.drain(); throw error }
            Issue.record("Cancelled action slept to normal completion"); return .null
        }
        let task = Task { try await broker.request(request) }
        let deadline = ContinuousClock.now + .seconds(3)
        while await !state.started {
            try #require(ContinuousClock.now < deadline, "Real action handler never started")
            try await Task.sleep(for: .milliseconds(1))
        }
        task.cancel()
        await #expect(throws: HanlinMiniAppRequestError.cancelled) { _ = try await task.value }
        #expect(await state.drained)
        #expect(await broker.auditEvents().last?.outcome == "cancelled")
    }

    private actor State {
        var started = false, drained = false
        func start() { started = true }
        func drain() { drained = true }
    }

    private func fixture() throws -> HanlinMiniAppRequest {
        .init(caller: try .init(validating: "lifetime.caller"), target: try .init(validating: "lifetime.target"),
              action: try .init(validating: "share.value"), capability: try .init(validating: "inter-app.share"), payload: .string("owned"))
    }
}
