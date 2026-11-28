import Foundation
import HanlinHostContracts
import HanlinPlatformContracts

/// Test-only host. Imports no Otzaria/Anytype module and calls no production app service.
public actor SyntheticFixtureHost: HanlinHostIntegration {
    public nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 0)
    public enum Mode: Sendable { case complete, deny, uncertainAfterDispatch, changeContextAfterDispatch }
    public private(set) var executions = 0
    public private(set) var nativeWrites = 0
    public private(set) var cancellations = 0
    private var current: HanlinHostContext
    private var mode: Mode = .complete
    public init(context: HanlinHostContext) { current = context }
    public func setMode(_ mode: Mode) { self.mode = mode }
    public func setContext(_ context: HanlinHostContext) { current = context }
    public func context(for session: HanlinHostSession) -> HanlinHostContext { current }

    public func catalog(for context: HanlinHostContext) throws -> HanlinHostCatalog {
        guard context == current else { throw HanlinHostError.staleContext }
        return .init(revision: .init(1), context: context, tools: try [
            Self.tool("fixture_read", risk: .read, guarantee: .readOnly),
            Self.tool("fixture_create", risk: .write, guarantee: .independentObjectCreation)
        ])
    }

    public static func tool(_ alias: String, risk: HanlinRiskLevel, guarantee: HanlinHostWriteGuarantee) throws -> HanlinHostTool {
        let logical = HanlinLogicalToolID(providerInstanceID: try .init(validating: "fixture.host"), localToolID: try .init(validating: alias))
        let revision = try HanlinDescriptorRevision(1)
        let schema = try HanlinJSONSchemaDocument.decodeCanonicalJSON(
            Data(#"{"type":"object","properties":{"text":{"type":"string","maxLength":4096}},"required":["text"],"additionalProperties":false}"#.utf8),
            defaultDialect: .draft2020_12)
        let descriptor = HanlinToolDescriptor(logicalID: logical, descriptorRevision: revision, owner: .system,
            title: try .init(["en": alias]), summary: try .init(["en": "Synthetic fixture operation"]),
            inputSchema: schema, risk: risk, presentation: .init())
        return .init(route: .init(alias: alias, logicalToolID: logical, descriptorRevision: revision), descriptor: descriptor, writeGuarantee: guarantee)
    }

    public func execute(_ invocation: HanlinHostInvocation,
                        progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        executions += 1
        guard invocation.session.context == current, invocation.request.origin == .assistantModel,
              invocation.request.routingTableRevision == .init(1), invocation.request.descriptorRevision == (try HanlinDescriptorRevision(1)),
              invocation.request.grantIDs.isEmpty,
              let deadline = invocation.request.deadline, deadline > Date() else { throw HanlinHostError.staleContext }
        guard invocation.expectedRevision == nil else { throw HanlinHostError.unsupportedConditionalWrite }
        let writing: Bool
        switch invocation.request.aliasUsed {
        case "fixture_read": writing = false
        case "fixture_create": writing = true
        default: throw HanlinHostError.unknownTool
        }
        // Real validation of this fixture's actual schema, not a pretend full JSON Schema validator.
        guard case .object(let members) = invocation.request.arguments, members.count == 1,
              case .string(let text)? = members["text"], text.count <= 4_096 else { throw HanlinHostError.invalidArguments }
        if mode == .deny {
            return .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
                outcome: .failed(.init(code: .permissionDenied, userMessage: "Fixture consent denied")), completedAt: .now),
                effectState: .notDispatched, context: invocation.session.context)
        }
        try Task.checkCancellation()
        guard invocation.session.context == current else { throw HanlinHostError.staleContext }
        if writing { nativeWrites += 1 }
        if mode == .uncertainAfterDispatch { throw CancellationError() }
        if mode == .changeContextAfterDispatch {
            current = .init(namespace: current.namespace, sceneID: current.sceneID, generation: UUID(), objectReference: current.objectReference)
        }
        // Two intentionally out-of-order messages exercise the dispatcher's monotonic filter.
        await progress(try .init(invocationID: invocation.request.id, sequence: 2, timestamp: .now, message: "Fixture progress"))
        await progress(try .init(invocationID: invocation.request.id, sequence: 1, timestamp: .now, message: "Stale progress"))
        return .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
            outcome: .completed([.text(writing ? "Created synthetic note" : "Synthetic snapshot")]), completedAt: .now),
            effectState: writing ? .confirmedCommitted : .confirmedNoEffect, context: invocation.session.context,
            reconciliationReference: writing ? invocation.request.id.rawValue : nil)
    }
    public func cancel(_ invocation: HanlinToolInvocationID) { cancellations += 1 }
    public func open(_ destination: HanlinHostDestination) throws -> HanlinHostNavigationResult {
        guard destination.context == current else { throw HanlinHostError.staleContext }
        // This headless fixture cannot claim a native scene/UI was mounted.
        return .queued(requestID: destination.requestID, context: current)
    }
}
