import Foundation
import Testing
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts

/// One-shot continuation gate. No timing sleeps or native/UI acceptance is implied.
private actor NavigationTransitionGate {
    private var arrived = false
    private var blocked: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func pause() async {
        await withCheckedContinuation { continuation in
            blocked = continuation
            arrived = true
            let waiting = observers
            observers.removeAll()
            for observer in waiting { observer.resume() }
        }
    }
    func waitUntilPaused() async {
        if arrived { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() {
        blocked?.resume()
        blocked = nil
    }
}

/// Explicit host double: the real dispatcher and complete original contracts are exercised.
private actor NavigationTransitionHost: HanlinHostNavigationTransitionSource {
    enum Mode: Sendable {
        case transition, stable, queued, queuedSuccessor, missingSuccessor, unregisteredSuccessor
        case wrongRequest, wrongObject, wrongBlock, normalizedObject, wrongOrigin
        case sameSessionID, sameGeneration, otherAccount, otherWorkspace, otherSpace, otherApp
        case otherScene, otherConversation, throwAfterEffect, legacyChangesContext
    }
    nonisolated let apiVersion: HanlinAPIVersion
    private var active: HanlinHostSession
    private let mode: Mode
    private let contextGate: NavigationTransitionGate?
    private let gatedContextCall: Int?
    private let beforeEffect: NavigationTransitionGate?
    private let afterEffect: NavigationTransitionGate?
    private(set) var contextCalls = 0
    private(set) var openCalls = 0
    private(set) var effects = 0
    private(set) var lastReceipt: HanlinHostNavigationReceipt?

    init(session: HanlinHostSession, mode: Mode = .transition,
         version: HanlinAPIVersion = .init(major: 1, minor: 2),
         contextGate: NavigationTransitionGate? = nil, gatedContextCall: Int? = nil,
         beforeEffect: NavigationTransitionGate? = nil, afterEffect: NavigationTransitionGate? = nil) {
        active = session
        self.mode = mode
        apiVersion = version
        self.contextGate = contextGate
        self.gatedContextCall = gatedContextCall
        self.beforeEffect = beforeEffect
        self.afterEffect = afterEffect
    }
    func context(for session: HanlinHostSession) async throws -> HanlinHostContext {
        guard session == active else { throw HanlinHostError.staleContext }
        let captured = active.context
        contextCalls += 1
        if contextCalls == gatedContextCall { await contextGate?.pause() }
        return captured
    }
    func replaceActive(_ session: HanlinHostSession) { active = session }
    func catalog(for context: HanlinHostContext) throws -> HanlinHostCatalog {
        guard context == active.context else { throw HanlinHostError.staleContext }
        return .init(revision: .init(1), context: context, tools: [])
    }
    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping HanlinHostProgressHandler) throws -> HanlinHostExecutionResult {
        throw HanlinHostError.unknownTool
    }
    func cancel(_ invocation: HanlinToolInvocationID) {}

    func open(_ destination: HanlinHostDestination) throws -> HanlinHostNavigationResult {
        guard destination.context == active.context else { throw HanlinHostError.staleContext }
        openCalls += 1
        effects += 1
        if mode == .legacyChangesContext { active = try successor(destination, from: active) }
        return .presented(requestID: destination.requestID, context: destination.context,
                          objectReference: destination.objectReference, blockReference: destination.blockReference)
    }

    private func successor(_ destination: HanlinHostDestination, from session: HanlinHostSession) throws -> HanlinHostSession {
        let old = session.context
        let namespace = try HanlinConversationNamespace(
            app: mode == .otherApp ? "different-app" : old.namespace.app,
            account: mode == .otherAccount ? "different-account" : old.namespace.account,
            workspace: mode == .otherWorkspace ? "different-workspace" : old.namespace.workspace,
            space: mode == .otherSpace ? "different-space" : old.namespace.space)
        let context = HanlinHostContext(namespace: namespace,
            sceneID: mode == .otherScene ? UUID() : old.sceneID,
            generation: mode == .sameGeneration ? old.generation : UUID(),
            objectReference: destination.objectReference,
            selectionReferences: destination.blockReference.map { [$0] } ?? [],
            sourceRevision: "observed-result-revision", localeIdentifier: old.localeIdentifier)
        return .init(id: mode == .sameSessionID ? session.id : UUID(),
                     conversationID: mode == .otherConversation ? UUID() : session.conversationID,
                     context: context)
    }

    func openWithContextTransition(_ destination: HanlinHostDestination,
                                   session: HanlinHostSession) async throws -> HanlinHostNavigationReceipt {
        guard session == active, destination.context == active.context else { throw HanlinHostError.staleContext }
        openCalls += 1
        await beforeEffect?.pause()
        let next = try successor(destination, from: session)
        let result: HanlinHostNavigationResult
        let successorSession: HanlinHostSession?
        if mode == .queued || mode == .queuedSuccessor {
            result = .queued(requestID: destination.requestID, context: session.context)
            successorSession = mode == .queuedSuccessor ? next : nil
        } else {
            effects += 1
            if mode != .stable && mode != .unregisteredSuccessor { active = next }
            result = .presented(requestID: mode == .wrongRequest ? UUID() : destination.requestID,
                context: destination.context,
                objectReference: mode == .wrongObject ? "other-book"
                    : mode == .normalizedObject ? destination.objectReference.decomposedStringWithCanonicalMapping
                    : destination.objectReference,
                blockReference: mode == .wrongBlock ? "other-block" : destination.blockReference)
            successorSession = mode == .stable || mode == .missingSuccessor ? nil : next
        }
        let origin = mode == .wrongOrigin
            ? HanlinHostSession(conversationID: session.conversationID, context: session.context) : session
        let receipt = HanlinHostNavigationReceipt(originalSession: origin, result: result,
                                                   successorSession: successorSession)
        lastReceipt = receipt
        await afterEffect?.pause()
        if mode == .throwAfterEffect { throw HanlinHostError.deadlineExceeded }
        return receipt
    }
}

private actor NavigationWithoutTransitionHost: HanlinHostIntegration {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 2)
    let original: NavigationTransitionHost
    init(_ original: NavigationTransitionHost) { self.original = original }
    func context(for session: HanlinHostSession) async throws -> HanlinHostContext { try await original.context(for: session) }
    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog { try await original.catalog(for: context) }
    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping HanlinHostProgressHandler) throws -> HanlinHostExecutionResult {
        throw HanlinHostError.unknownTool
    }
    func cancel(_ invocation: HanlinToolInvocationID) {}
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult { try await original.open(destination) }
}

private struct NavigationFixture: Sendable {
    let host: NavigationTransitionHost
    let dispatcher: HanlinHostDispatcher
    let session: HanlinHostSession
    let destination: HanlinHostDestination
}

@MainActor
struct NavigationTransitionTests {
    private func fixture(_ mode: NavigationTransitionHost.Mode = .transition,
                         version: HanlinAPIVersion = .init(major: 1, minor: 2),
                         contextGate: NavigationTransitionGate? = nil, contextCall: Int? = nil,
                         before: NavigationTransitionGate? = nil, after: NavigationTransitionGate? = nil) throws -> NavigationFixture {
        let namespace = try HanlinConversationNamespace(app: "original-host", account: "local-account",
                                                        workspace: "original-workspace", space: "original-backend")
        let context = HanlinHostContext(namespace: namespace, sceneID: UUID(), generation: UUID(),
                                       objectReference: "original-book", sourceRevision: "original-revision")
        let session = HanlinHostSession(conversationID: UUID(), context: context)
        let host = NavigationTransitionHost(session: session, mode: mode, version: version,
            contextGate: contextGate, gatedContextCall: contextCall, beforeEffect: before, afterEffect: after)
        return .init(host: host, dispatcher: HanlinHostDispatcher(host: host), session: session,
                     destination: .init(context: context, objectReference: "requested-café", blockReference: "source-line-7"))
    }

    private func rejects(_ expected: HanlinHostError, _ body: () async throws -> Void,
                         sourceLocation: SourceLocation = #_sourceLocation) async {
        do { try await body(); Issue.record("Expected \(expected)", sourceLocation: sourceLocation) }
        catch { #expect(error as? HanlinHostError == expected, sourceLocation: sourceLocation) }
    }
    private func rejectsCancellation(_ body: () async throws -> Void,
                                     sourceLocation: SourceLocation = #_sourceLocation) async {
        do { try await body(); Issue.record("Expected task cancellation", sourceLocation: sourceLocation) }
        catch { #expect(error is CancellationError, sourceLocation: sourceLocation) }
    }

    @Test func originalRequestAndFreshSuccessorAreAcknowledgedExactly() async throws {
        let f = try fixture()
        let receipt = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session)
        try receipt.validate(for: f.destination, session: f.session)
        #expect(receipt.presentationAcknowledged)
        let next = try #require(receipt.successorSession)
        #expect(next.id != f.session.id)
        #expect(next.context.generation != f.session.context.generation)
        #expect(next.conversationID == f.session.conversationID)
        #expect(next.context.namespace == f.session.context.namespace)
        #expect(next.context.sceneID == f.session.context.sceneID)
        let subsequent = HanlinHostDestination(context: next.context, objectReference: "stable-panel")
        let ack = try await f.dispatcher.open(subsequent, session: next)
        #expect(ack.presentationAcknowledged)
        #expect(await f.host.effects == 2)
    }

    @Test func retiredOriginCannotBecomeValidByReplayingItsOldContext() async throws {
        let f = try fixture()
        _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session)
        await f.host.replaceActive(f.session)
        await rejects(.staleContext) { _ = try await f.dispatcher.open(f.destination, session: f.session) }
        #expect(await f.host.openCalls == 1)
    }

    @Test func originalOpenStillRejectsAChangedContentContext() async throws {
        let f = try fixture(.legacyChangesContext)
        await rejects(.staleContext) { _ = try await f.dispatcher.open(f.destination, session: f.session) }
        #expect(await f.host.effects == 1)
    }

    @Test func stablePresentationRetainsTheOriginalSession() async throws {
        let f = try fixture(.stable)
        let receipt = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session)
        #expect(receipt.presentationAcknowledged)
        #expect(receipt.successorSession == nil)
        let other = HanlinHostDestination(context: f.session.context, objectReference: "other-stable-panel")
        _ = try await f.dispatcher.open(other, session: f.session)
        #expect(await f.host.openCalls == 2)
    }

    @Test func queuedIsNotPresentationAndCannotBeReentered() async throws {
        let f = try fixture(.queued)
        let receipt = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session)
        #expect(!receipt.presentationAcknowledged)
        #expect(receipt.successorSession == nil)
        await rejects(.duplicateInvocation) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        #expect(await f.host.openCalls == 1)
        #expect(await f.host.effects == 0)
    }

    @Test func reservedRequestRejectsChangedOpaqueDestinationBytes() async throws {
        let f = try fixture(.queued)
        _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session)
        let changed = HanlinHostDestination(requestID: f.destination.requestID, context: f.session.context,
            objectReference: f.destination.objectReference.decomposedStringWithCanonicalMapping,
            blockReference: f.destination.blockReference)
        #expect(changed.objectReference == f.destination.objectReference)
        #expect(!changed.objectReference.utf8.elementsEqual(f.destination.objectReference.utf8))
        await rejects(.idempotencyConflict) { _ = try await f.dispatcher.openWithContextTransition(changed, session: f.session) }
        #expect(await f.host.openCalls == 1)
    }

    @Test func capabilityVersionIsRequiredBeforeAnyHostEntry() async throws {
        for version in [HanlinAPIVersion(major: 1, minor: 1), .init(major: 2, minor: 0)] {
            let f = try fixture(version: version)
            await rejects(.unsupportedVersion) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
            #expect(await f.host.openCalls == 0)
            #expect(await f.host.contextCalls == 0)
        }
    }

    @Test func versionAloneCannotInventTheHostCapability() async throws {
        let f = try fixture()
        let dispatcher = HanlinHostDispatcher(host: NavigationWithoutTransitionHost(f.host))
        await rejects(.unsupportedVersion) { _ = try await dispatcher.openWithContextTransition(f.destination, session: f.session) }
        #expect(await f.host.openCalls == 0)
        #expect(await f.host.contextCalls == 0)
    }

    @Test func foreignDestinationContextNeverNavigates() async throws {
        let f = try fixture()
        let other = try fixture()
        let destination = HanlinHostDestination(context: other.session.context, objectReference: "other")
        await rejects(.staleContext) { _ = try await f.dispatcher.openWithContextTransition(destination, session: f.session) }
        #expect(await f.host.openCalls == 0)
    }

    @Test func alreadyStaleAndRevokedSessionsNeverNavigate() async throws {
        let stale = try fixture()
        let other = try fixture()
        await stale.host.replaceActive(other.session)
        await rejects(.staleContext) { _ = try await stale.dispatcher.openWithContextTransition(stale.destination, session: stale.session) }
        #expect(await stale.host.openCalls == 0)
        let revoked = try fixture()
        await revoked.dispatcher.invalidate(revoked.session)
        await rejects(.staleContext) { _ = try await revoked.dispatcher.openWithContextTransition(revoked.destination, session: revoked.session) }
        #expect(await revoked.host.openCalls == 0)
    }

    @Test func requestTargetBlockAndOriginMustAllMatchExactly() async throws {
        for mode in [NavigationTransitionHost.Mode.wrongRequest, .wrongObject, .wrongBlock, .normalizedObject, .wrongOrigin] {
            let f = try fixture(mode)
            await rejects(.resultMismatch) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
            #expect(await f.host.effects == 1)
            #expect(await f.dispatcher.navigationReceipts(for: f.session).isEmpty)
        }
    }

    @Test func successorCannotChangeAccountWorkspaceBackendAppSceneOrConversation() async throws {
        for mode in [NavigationTransitionHost.Mode.otherAccount, .otherWorkspace, .otherSpace, .otherApp, .otherScene, .otherConversation] {
            let f = try fixture(mode)
            await rejects(.resultMismatch) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
            #expect(await f.host.effects == 1)
        }
    }

    @Test func successorRequiresNewSessionAndGeneration() async throws {
        for mode in [NavigationTransitionHost.Mode.sameSessionID, .sameGeneration] {
            let f = try fixture(mode)
            await rejects(.resultMismatch) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
            #expect(await f.host.effects == 1)
        }
    }

    @Test func queuedCannotIssueASuccessor() async throws {
        let f = try fixture(.queuedSuccessor)
        await rejects(.resultMismatch) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        #expect(await f.host.effects == 0)
    }

    @Test func returnedSuccessorMustBeRegisteredByTheLiveHost() async throws {
        let f = try fixture(.unregisteredSuccessor)
        await rejects(.staleContext) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        #expect(await f.host.effects == 1)
        #expect(await f.dispatcher.navigationReceipts(for: f.session).count == 1)
    }

    @Test func changedContextWithoutASuccessorStillFailsFreshness() async throws {
        let f = try fixture(.missingSuccessor)
        await rejects(.staleContext) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        #expect(await f.host.effects == 1)
    }

    @Test func revocationDuringInitialContextAwaitPreventsHostEntry() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(contextGate: gate, contextCall: 1)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        await f.dispatcher.invalidate(f.session)
        await gate.release()
        await rejects(.staleContext) { _ = try await task.value }
        #expect(await f.host.openCalls == 0)
    }

    @Test func cancellationDuringInitialContextAwaitPreventsHostEntry() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(contextGate: gate, contextCall: 1)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        await rejectsCancellation { _ = try await task.value }
        #expect(await f.host.openCalls == 0)
    }

    @Test func inFlightTransitionBlocksAnotherOriginalSessionOperation() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(before: gate)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        let other = HanlinHostDestination(context: f.session.context, objectReference: "different-destination")
        await rejects(.staleContext) { _ = try await f.dispatcher.open(other, session: f.session) }
        await rejects(.staleContext) { _ = try await f.dispatcher.openWithContextTransition(other, session: f.session) }
        #expect(await f.host.openCalls == 1)
        await gate.release()
        _ = try await task.value
    }

    @Test func originRevokedAfterEffectSuppressesAckButRetainsReceipt() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(after: gate)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        await f.dispatcher.invalidate(f.session)
        await gate.release()
        await rejects(.staleContext) { _ = try await task.value }
        #expect(await f.host.effects == 1)
        #expect(await f.dispatcher.navigationReceipts(for: f.session).count == 1)
    }

    @Test func cancellationAfterEffectSuppressesAckButRetainsReceipt() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(after: gate)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        await rejectsCancellation { _ = try await task.value }
        #expect(await f.host.effects == 1)
        #expect(await f.dispatcher.navigationReceipts(for: f.session).count == 1)
    }

    @Test func originRevokedDuringSuccessorContextAwaitCannotReceiveAck() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(contextGate: gate, contextCall: 2)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        await f.dispatcher.invalidate(f.session)
        await gate.release()
        await rejects(.staleContext) { _ = try await task.value }
        #expect(await f.dispatcher.navigationReceipts(for: f.session).count == 1)
    }

    @Test func successorRevokedDuringItsContextAwaitCannotReceiveAck() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(contextGate: gate, contextCall: 2)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        let receipt = try #require(await f.host.lastReceipt)
        let next = try #require(receipt.successorSession)
        await f.dispatcher.invalidate(next)
        await gate.release()
        await rejects(.staleContext) { _ = try await task.value }
        #expect(await f.dispatcher.navigationReceipts(for: f.session).count == 1)
    }

    @Test func cancellationDuringSuccessorContextAwaitCannotReceiveAck() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(contextGate: gate, contextCall: 2)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        await rejectsCancellation { _ = try await task.value }
        #expect(await f.dispatcher.navigationReceipts(for: f.session).count == 1)
    }

    @Test func unrelatedAuthorityChangeAfterEffectCannotReceiveAck() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(after: gate)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        let other = try fixture()
        await f.host.replaceActive(other.session)
        await gate.release()
        await rejects(.staleContext) { _ = try await task.value }
        #expect(await f.host.effects == 1)
        #expect(await f.dispatcher.navigationReceipts(for: f.session).count == 1)
    }

    @Test func thrownPostEffectResultCannotBeRetriedEvenIfOldContextReappears() async throws {
        let f = try fixture(.throwAfterEffect)
        await rejects(.deadlineExceeded) { _ = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await f.host.replaceActive(f.session)
        let retry = HanlinHostDestination(context: f.session.context, objectReference: f.destination.objectReference)
        await rejects(.staleContext) { _ = try await f.dispatcher.openWithContextTransition(retry, session: f.session) }
        #expect(await f.host.effects == 1)
        #expect(await f.dispatcher.navigationReceipts(for: f.session).isEmpty)
    }

    @Test func cancelledReceiptCannotAuthorizeItsUndeliveredSuccessor() async throws {
        let gate = NavigationTransitionGate()
        let f = try fixture(after: gate)
        let task = Task { try await f.dispatcher.openWithContextTransition(f.destination, session: f.session) }
        await gate.waitUntilPaused()
        task.cancel()
        await gate.release()
        await rejectsCancellation { _ = try await task.value }
        let receipts = await f.dispatcher.navigationReceipts(for: f.session)
        let next = try #require(receipts.first?.successorSession)
        let followUp = HanlinHostDestination(context: next.context, objectReference: "unacknowledged-continuation")
        await rejects(.staleContext) { _ = try await f.dispatcher.open(followUp, session: next) }
        await rejects(.staleContext) { _ = try await f.dispatcher.openWithContextTransition(followUp, session: next) }
        #expect(await f.host.effects == 1)
        #expect(receipts.count == 1)
    }

    @Test func receiptRoundTripPreservesCorrelationWithoutGrantingCurrentAuthority() async throws {
        let f = try fixture()
        let receipt = try await f.dispatcher.openWithContextTransition(f.destination, session: f.session)
        let decoded = try JSONDecoder().decode(HanlinHostNavigationReceipt.self, from: JSONEncoder().encode(receipt))
        #expect(decoded == receipt)
        try decoded.validate(for: f.destination, session: f.session)
        let wrongOwner = HanlinHostSession(id: f.session.id, conversationID: UUID(), context: f.session.context)
        #expect(await f.dispatcher.navigationReceipts(for: wrongOwner).isEmpty)
        #expect(await f.dispatcher.navigationReceipts(for: f.session) == [receipt])
    }
}
