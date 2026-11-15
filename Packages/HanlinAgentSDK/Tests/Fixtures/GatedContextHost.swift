import Foundation
import HanlinHostContracts
import HanlinPlatformContracts

/// Deterministic race fixture: captures an authorized context, signals suspension, then returns
/// that old matching value only when the test releases it. No sleeps or real host/UI calls.
public actor GatedContextHost: HanlinHostIntegration {
    public nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    public let base: SyntheticFixtureHost
    public private(set) var openCalls = 0
    private var contextCalls = 0
    private var gatedCall: Int?
    private var heldContext: CheckedContinuation<Void, Never>?
    private var waitingForGate: [CheckedContinuation<Void, Never>] = []
    private let forwardProgress: Bool

    public init(context: HanlinHostContext, forwardProgress: Bool = false) {
        self.base = SyntheticFixtureHost(context: context)
        self.forwardProgress = forwardProgress
    }

    /// 1 gates the next context request; 2 gates the request following that one.
    public func gateContext(after calls: Int = 1) {
        precondition(calls > 0 && heldContext == nil && gatedCall == nil)
        gatedCall = contextCalls + calls
    }
    public func waitUntilContextIsSuspended() async {
        if heldContext != nil { return }
        await withCheckedContinuation { waitingForGate.append($0) }
    }
    public func releaseCapturedContext() {
        precondition(heldContext != nil)
        let held = heldContext
        heldContext = nil
        gatedCall = nil
        held?.resume()
    }
    public func context(for session: HanlinHostSession) async throws -> HanlinHostContext {
        contextCalls += 1
        let call = contextCalls
        let captured = await base.context(for: session)
        if gatedCall == call {
            await withCheckedContinuation { continuation in
                heldContext = continuation
                let waiters = waitingForGate
                waitingForGate.removeAll()
                for waiter in waiters { waiter.resume() }
            }
        }
        return captured
    }
    public func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog { try await base.catalog(for: context) }
    public func execute(_ invocation: HanlinHostInvocation,
                        progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        if forwardProgress { return try await base.execute(invocation, progress: progress) }
        return try await base.execute(invocation, progress: { _ in })
    }
    public func cancel(_ invocation: HanlinToolInvocationID) async { await base.cancel(invocation) }
    public func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult {
        openCalls += 1
        _ = try await base.open(destination)
        // Scripted ACK solely to exercise stale delivery rejection. Never native UI evidence.
        return .presented(requestID: destination.requestID, context: destination.context,
                          objectReference: destination.objectReference, blockReference: destination.blockReference)
    }
}
