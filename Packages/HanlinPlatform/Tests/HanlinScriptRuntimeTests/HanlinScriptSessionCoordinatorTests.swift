import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptRuntime
import Testing

@Suite("Scripting runtime v2 session coordinator")
struct HanlinScriptSessionCoordinatorTests {
    @Test("Enforces the complete lifecycle and idempotent close")
    func lifecycle() async throws {
        let session = try makeSession()
        #expect(await session.resourceSnapshot().state == .created)
        try await session.beginLoading()
        try await session.activate()
        try await session.suspend()
        try await session.resume()
        await session.close()
        await session.close()
        let snapshot = await session.resourceSnapshot()
        #expect(snapshot.state == .closed)
        await #expect(throws: HanlinScriptSessionError.inactive(.closed)) {
            try await session.registerPromise(HanlinPromiseID(validating: "promise.closed"))
        }
    }

    @Test("Owns and releases promises, callbacks, subscriptions, and handles")
    func resources() async throws {
        let session = try makeSession()
        try await session.beginLoading()
        try await session.activate()
        let promise = try HanlinPromiseID(validating: "promise.1")
        let callback = try HanlinCallbackID(validating: "callback.1")
        let subscription = try HanlinSubscriptionID(validating: "subscription.1")
        let handle = try HanlinObjectHandleID(validating: "handle.1")
        try await session.registerPromise(promise)
        try await session.registerCallback(callback)
        try await session.subscribe(subscription)
        try await session.retainHandle(handle)
        var snapshot = await session.resourceSnapshot()
        #expect(snapshot.pendingPromises == 1)
        #expect(snapshot.callbacks == 1)
        #expect(snapshot.subscriptions == 1)
        #expect(snapshot.objectHandles == 1)
        #expect(await session.settlePromise(promise))
        #expect(await session.releaseCallback(callback))
        #expect(await session.unsubscribe(subscription))
        #expect(await session.releaseHandle(handle))
        snapshot = await session.resourceSnapshot()
        #expect(snapshot.pendingPromises == 0)
        await session.fail()
        #expect(await session.resourceSnapshot().state == .failed)
    }

    @Test("Applies quotas and queue backpressure")
    func limits() async throws {
        let session = try makeSession(maximum: 1)
        try await session.beginLoading()
        try await session.activate()
        try await session.registerPromise(HanlinPromiseID(validating: "promise.1"))
        await #expect(throws: HanlinScriptSessionError.pendingPromiseLimit) {
            try await session.registerPromise(HanlinPromiseID(validating: "promise.2"))
        }
        try await session.enqueue(kind: .event, payload: .string("first"))
        await #expect(throws: HanlinScriptSessionError.eventBackpressure) {
            try await session.enqueue(kind: .event, payload: .string("second"))
        }
        #expect(await session.dequeue()?.sequence == 1)
        try await session.enqueue(kind: .event, payload: .string("second"))
        #expect(await session.dequeue()?.sequence == 2)
    }

    @Test("Rejects cross-session envelopes and inbound replay")
    func isolationAndReplay() async throws {
        let session = try makeSession()
        let wrong = HanlinScriptEnvelope(
            protocolVersion: .init(major: 2, minor: 0),
            sessionID: try HanlinSessionID(validating: "session.other"),
            sequence: 1,
            kind: .event,
            payload: .null
        )
        await #expect(throws: HanlinScriptSessionError.wrongSession) {
            try await session.acceptInbound(wrong)
        }
        let valid = HanlinScriptEnvelope(
            protocolVersion: .init(major: 2, minor: 0),
            sessionID: try HanlinSessionID(validating: "session.fixture"),
            sequence: 1,
            kind: .event,
            payload: .null
        )
        try await session.acceptInbound(valid)
        await #expect(throws: HanlinScriptSessionError.sequenceRegression) {
            try await session.acceptInbound(valid)
        }
    }

    @Test("Context policies are distinct and valid")
    func policies() throws {
        let app = try HanlinScriptExecutionPolicy.standard(for: .mainApplication)
        let widget = try HanlinScriptExecutionPolicy.standard(for: .widget)
        let background = try HanlinScriptExecutionPolicy.standard(for: .backgroundTask)
        #expect(app.memoryBytes > widget.memoryBytes)
        #expect(background.deadlineMilliseconds > widget.deadlineMilliseconds)
        #expect(Set(try HanlinExecutionContext.allCases.map {
            try HanlinScriptExecutionPolicy.standard(for: $0).context
        }) == Set(HanlinExecutionContext.allCases))
    }

    private func makeSession(maximum: Int = 4) throws -> HanlinScriptSessionCoordinator {
        let context = HanlinExecutionContext.mainApplication
        let policy = try HanlinScriptExecutionPolicy(
            id: "test-v1",
            context: context,
            memoryBytes: 1 << 20,
            stackBytes: 128 << 10,
            deadlineMilliseconds: 1_000,
            maximumOutputBytes: 1_024,
            maximumQueuedEvents: maximum,
            maximumPendingPromises: maximum,
            maximumCallbacks: maximum,
            maximumObjectHandles: maximum,
            maximumStorageBytes: 1_024
        )
        return HanlinScriptSessionCoordinator(descriptor: .init(
            sessionID: try HanlinSessionID(validating: "session.fixture"),
            installedPackageID: try HanlinInstalledPackageID(validating: "package.fixture"),
            entrypointID: "app",
            context: context,
            policy: policy
        ))
    }
}
