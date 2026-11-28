import Foundation
import HanlinPlatformContracts

public struct HanlinHostInvocation: Sendable {
    public let request: HanlinToolInvocationRequest
    public let session: HanlinHostSession
    /// Reserved once by the Dispatcher before Host entry; durable origin association can retain it.
    public let resultID: UUID
    public let runID: UUID
    public let step: Int
    public let providerCallID: String
    public let writeGuarantee: HanlinHostWriteGuarantee
    /// Original accepted input before the portable numeric projection. Never reconstruct it from request.arguments.
    public let originalArgumentsJSON: Data?
    public let expectedRevision: String?
    public init(request: HanlinToolInvocationRequest, session: HanlinHostSession, runID: UUID,
                step: Int, providerCallID: String, writeGuarantee: HanlinHostWriteGuarantee, expectedRevision: String? = nil,
                originalArgumentsJSON: Data? = nil, resultID: UUID = UUID()) {
        self.resultID = resultID
        self.originalArgumentsJSON = originalArgumentsJSON
        self.request = request; self.session = session; self.runID = runID; self.step = step
        self.providerCallID = providerCallID; self.writeGuarantee = writeGuarantee; self.expectedRevision = expectedRevision
    }
}

public enum HanlinHostEffectState: String, Codable, Sendable {
    case notDispatched, confirmedNoEffect, confirmedCommitted, uncertain
}

public struct HanlinHostExecutionResult: Codable, Hashable, Sendable {
    public let result: HanlinToolInvocationResult
    public let effectState: HanlinHostEffectState
    public let context: HanlinHostContext
    /// Opaque host receipt, not a business document or executable permission.
    public let reconciliationReference: String?
    public init(result: HanlinToolInvocationResult, effectState: HanlinHostEffectState,
                context: HanlinHostContext, reconciliationReference: String? = nil) {
        self.result = result; self.effectState = effectState; self.context = context
        self.reconciliationReference = reconciliationReference
    }

    /// Default persistence projection excludes business payloads and raw host error details.
    /// Hosts rehydrate opaque scoped references through their current authority when needed.
    public func metadataReceipt() -> Self {
        let outcome: HanlinToolOutcome
        switch result.outcome {
        case .completed: outcome = .completed([])
        case .failed(let error): outcome = .failed(.init(code: error.code, userMessage: "Host operation failed"))
        case .denied(let id, _): outcome = .denied(id, "Host operation denied")
        case .cancelled(let id, _): outcome = .cancelled(id, stage: "host")
        case .timedOut(let deadline, let cleanup): outcome = .timedOut(deadline: deadline, cleanupCompleted: cleanup)
        }
        return .init(result: .init(invocationID: result.invocationID, logicalToolID: result.logicalToolID,
            outcome: outcome, startedAt: result.startedAt, completedAt: result.completedAt),
            effectState: effectState, context: context, reconciliationReference: reconciliationReference)
    }
}

public struct HanlinHostDestination: Codable, Hashable, Sendable {
    public let requestID: UUID
    public let context: HanlinHostContext
    public let objectReference: String
    public let blockReference: String?
    public init(requestID: UUID = UUID(), context: HanlinHostContext, objectReference: String, blockReference: String? = nil) {
        self.requestID = requestID; self.context = context; self.objectReference = objectReference; self.blockReference = blockReference
    }
}

/// Only the actual scene/UI owner may issue presented acknowledgement, after exact-target mount.
public enum HanlinHostNavigationResult: Codable, Hashable, Sendable {
    case queued(requestID: UUID, context: HanlinHostContext)
    case presented(requestID: UUID, context: HanlinHostContext, objectReference: String, blockReference: String?)

    public func validate(for destination: HanlinHostDestination) throws {
        switch self {
        case .queued(let id, let context):
            guard id == destination.requestID, context == destination.context else { throw HanlinHostError.resultMismatch }
        case .presented(let id, let context, let object, let block):
            guard id == destination.requestID, context == destination.context,
                  object.utf8.elementsEqual(destination.objectReference.utf8),
                  block.map({ Data($0.utf8) }) == destination.blockReference.map({ Data($0.utf8) }) else { throw HanlinHostError.resultMismatch }
        }
    }
    public var presentationAcknowledged: Bool { if case .presented = self { return true }; return false }
}

/// Keep the callback's concurrency convention defined by this SDK module. Consumers
/// may enable NonisolatedNonsendingByDefault without changing the protocol witness type.
public typealias HanlinHostProgressHandler = @Sendable (HanlinToolProgressEvent) async -> Void

/// The host is the live authority. No SDK grant store or implicit always-allow adapter.
public protocol HanlinHostIntegration: Sendable {
    var apiVersion: HanlinAPIVersion { get }
    func context(for session: HanlinHostSession) async throws -> HanlinHostContext
    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog
    /// Must validate actual JSON Schema, live context/revision, operation permissions and cancellation
    /// at the last available dispatch boundary. Conditional mutations require native atomic support.
    /// After dispatch, record/return uncertain outcomes rather than asserting rollback on cancellation.
    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping HanlinHostProgressHandler) async throws -> HanlinHostExecutionResult
    func cancel(_ invocation: HanlinToolInvocationID) async
    /// A queued return is NOT successful presentation; await an exact scene/UI acknowledgement.
    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult
}

public protocol HanlinHostPermissionService: Sendable {
    func request(_ request: HanlinPermissionRequest) async throws -> HanlinPermissionDecision
    func effectivePermission(for request: HanlinPolicyEvaluationRequest) async throws -> HanlinEffectivePermission
    func revoke(_ revocation: HanlinPermissionRevocation) async throws
}

public struct HanlinModelReference: Codable, Hashable, Sendable {
    public let provider: String
    public let modelID: String
    public init(provider: String, modelID: String) { self.provider = provider; self.modelID = modelID }
}

public protocol HanlinCredentialResolver: Sendable {
    /// Transient return only. Host chooses Keychain and entitlement policy.
    func credential(for model: HanlinModelReference, namespace: HanlinConversationNamespace) async throws -> String
}

public struct HanlinAttachmentReference: Codable, Hashable, Sendable {
    public let handle: UUID
    public let namespace: HanlinConversationNamespace
    public let mediaType: String
    public let byteCount: Int
    public init(handle: UUID, namespace: HanlinConversationNamespace, mediaType: String, byteCount: Int) {
        self.handle = handle; self.namespace = namespace; self.mediaType = mediaType; self.byteCount = byteCount
    }
}

public protocol HanlinAttachmentStore: Sendable {
    func importData(_ data: Data, mediaType: String, session: HanlinHostSession) async throws -> HanlinAttachmentReference
    func read(_ reference: HanlinAttachmentReference, session: HanlinHostSession) async throws -> Data
    func remove(_ reference: HanlinAttachmentReference, session: HanlinHostSession) async throws
}

public protocol HanlinMemoryStore: Sendable {
    func read(namespace: HanlinConversationNamespace) async throws -> [String]
    func replace(_ memories: [String], namespace: HanlinConversationNamespace) async throws
}

/// Host owns authentication/connections; SDK consumes authorized step exposure and instructions.
public struct HanlinHostStepPreparation: Sendable {
    public let activeAliases: [String]
    public let skillIDs: [String]
    public let instructions: [String]
    public init(activeAliases: [String], skillIDs: [String] = [], instructions: [String] = []) {
        self.activeAliases = activeAliases; self.skillIDs = skillIDs; self.instructions = instructions
    }
}
public protocol HanlinHostCapabilitySource: Sendable {
    func prepareStep(_ step: Int, session: HanlinHostSession) async throws -> HanlinHostStepPreparation
}

/// Diagnostics are intentionally metadata-only. Raw prompts/arguments/credentials are not accepted.
public struct HanlinDiagnosticEvent: Sendable {
    public enum Kind: String, Sendable { case runStarted, runFinished, cancelled, hostFailure, uncertainWrite }
    public let kind: Kind
    public let runID: UUID
    public init(kind: Kind, runID: UUID) { self.kind = kind; self.runID = runID }
}
public protocol HanlinDiagnosticsSink: Sendable { func record(_ event: HanlinDiagnosticEvent) async }
